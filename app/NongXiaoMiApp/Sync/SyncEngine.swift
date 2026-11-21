import Foundation
import NongXiaoMiCore

// MARK: - 同步引擎: 主流程编排(Sync.java + Backup.java 的移植)
//
// Android架构对应:
// - SyncService常驻服务: 长轮询/api/aver看守会话(被踢秒级403) + 每唤醒tick
// - tick = pushPool(账号池只上传) + pushPending(组推送) + fetchGroupData(组拉取)
// - 账号池云→本地只有重登录整库恢复(restoreOnLogin)这一条路
// - 主管/分管数据互通走协作组接口, 不走账号池
//
// iOS架构: 前台期间周期tick + 长轮询看守; 后台靠系统唤醒后补tick。

final class SyncEngine {

    let db: FarmDb
    let api: ApiClient
    weak var state: AppState?
    private let prefs = UserDefaults.standard
    private var ticking = false

    /// 照片压缩(App层用UIKit; 各端重压base64必不同, 协议里contentKey已排除照片)
    var compressPhoto: (String) -> Data? = { _ in nil }

    init(db: FarmDb, api: ApiClient, state: AppState) {
        self.db = db
        self.api = api
        self.state = state
    }

    // MARK: - 一轮完整同步

    func tick() {
        guard !ticking else { return }
        let token = api.token
        guard !token.isEmpty, !api.phone.isEmpty else { return }
        ticking = true
        Task {
            defer { ticking = false }
            do {
                try await pushPool()          // ① 账号池上传(只增不删, 服务端去重)
                try await pushGroup()         // ② 组数据推送(分管→主管)
                try await fetchGroupData()    // ③ 组数据拉取落地(主管改动自动传导)
                await MainActor.run { self.state?.lastSyncAt = Date() }
            } catch let e as ApiError where e.code == 403 {
                // 被踢(token失效/单设备在线): 弹回登录页(对应checkKicked)
                await MainActor.run { self.state?.doLogout() }
            } catch {
                // 网络失败静默, 下次tick再试(本地已落库, 不丢数据)
                await MainActor.run {
                    self.state?.syncMessage = "同步稍后重试"
                }
            }
        }
    }

    /// 长轮询池版本看守(对应waitPoolChange): 挂起最多25秒, 有变化立即返回。
    /// 被踢时服务端秒级403 → 返回false
    func awaitPoolChange(seen: Int64) async -> (changed: Bool, version: Int64, kicked: Bool) {
        do {
            let r = try await api.awaitPoolVersion(since: String(seen))
            let v = Int64((r["version"] as? Int) ?? Int(seen))
            return (v != seen, v, false)
        } catch let e as ApiError where e.code == 403 {
            return (false, seen, true)
        } catch {
            return (false, seen, false)
        }
    }

    // MARK: - 组数据拉取落地 (Sync.fetchGroupData:130-212)

    func fetchGroupData() async throws {
        guard !api.token.isEmpty else { return }
        let roles = try await getRoles()
        let vers = try await groupVers()

        for (role, code) in roles {
            let v = vers[code]
            if role == "B" {
                // 主管: 组内分管数据自动并入(审批改动自动传导)
                if let v, v == prefs.string(forKey: "pull_dver_" + code) ?? "" { continue }
                let s = try await api.summary(code: code)
                guard (s["ok"] as? Bool) == true else { continue }
                _ = await importRemote(recs: s["records"] as? [[String: Any]],
                                       leds: s["ledger"] as? [[String: Any]])
                if let v { prefs.set(v, forKey: "pull_dver_" + code) }
                continue
            }
            guard role == "L" else { continue }
            // 版本门: 没变的组跳过全量拉取(1.5MB全量→几KB的myroles)
            if let v, v == prefs.string(forKey: "gdvers_" + code) ?? "" { continue }
            let r = try await api.read(code: code, want: "records")
            guard (r["ok"] as? Bool) == true else { continue }

            // 地块同步: 主管圈定地块+圈定图落到本地
            var names: [String] = []
            if let plots = r["plots"] as? [[String: Any]] {
                let have = Set(db.listPlots().map { $0.name })
                for pl in plots {
                    let nm = str(pl, "name")
                    if nm.isEmpty { continue }
                    names.append(nm)
                    let thumb = saveB64(str(pl, "thumb_b64"))
                    if have.contains(nm) {
                        // 已有同名地块: 不覆盖本地数据; 仅当本地是"授权壳"
                        // (带主管边界、还没圈定图)时回填圈定图, 其余一律不动
                        if let lp = db.listPlots().first(where: { $0.name == nm }),
                           lp.thumb.isEmpty, !lp.polygon.isEmpty, !thumb.isEmpty {
                            db.updatePlotData(name: nm, polygon: lp.polygon,
                                              area: lp.area, thumb: thumb, center: lp.center)
                        }
                        continue
                    }
                    db.addPlot(name: nm, polygon: str(pl, "polygon"),
                               area: (pl["area"] as? Double) ?? 0,
                               thumb: thumb, center: str(pl, "center"))
                }
            }
            prefs.set(names.joined(separator: ";"), forKey: "sync_plots_" + code)
            _ = await importRemote(recs: r["records"] as? [[String: Any]],
                                   leds: r["ledger"] as? [[String: Any]])
            if let v { prefs.set(v, forKey: "gdvers_" + code) }
        }
    }

    /// 版本门数据源(对应Sync.groupVers: myroles带vers=code:dataVer:poolVer:授权摘要)
    func groupVers() async throws -> [String: String] {
        let r = try await api.myRoles()
        var out: [String: String] = [:]
        if let groups = r["groups"] as? [[String: Any]] {
            for g in groups {
                let code = str(g, "code")
                let v = str(g, "vers")
                if !code.isEmpty, !v.isEmpty { out[code] = v }
            }
        }
        return out
    }

    func getRoles() async throws -> [(role: String, code: String)] {
        let r = try await api.myRoles()
        var out: [(String, String)] = []
        if let groups = r["groups"] as? [[String: Any]] {
            for g in groups {
                let role = str(g, "role"), code = str(g, "code")
                if !code.isEmpty { out.append((role, code)) }
            }
        }
        return out
    }

    // MARK: - 远端导入 (Sync.importRemote:742-832 逐行移植)

    @discardableResult
    func importRemote(recs: [[String: Any]]?, leds: [[String: Any]]?) async -> (recs: Int, leds: Int) {
        var out = (0, 0)
        let myPhone = api.phone  // 组数据按账号标记device: 自己上报的不导回(防自我复制)
        if let recs {
            for dict in recs {
                guard let it = RemoteRecord(dict: dict) else { continue }
                if !myPhone.isEmpty, myPhone == it.device { continue }
                // 墓碑行: 本地副本一并删除(删除传导; 也用于清洗历史分裂行)
                if it.deleted {
                    if db.hasRecordHash(it.uuid) { db.deleteByUuid(it.uuid) }
                    continue
                }
                if db.hasRecordHash(it.uuid) {
                    // 本机已有同号记录: 先比新旧再就地更新, 不再被内容去重拦截
                    let local = db.listRecords().first { $0.hash == it.uuid }
                    let decision = MergeRules.importRecord(
                        local: local?.farmRecord, incoming: it.asLocal)
                    guard decision == .update else { continue }
                    if db.updateRecordByUuid(it.uuid, date: it.date, plot: it.plot,
                                             crop: it.crop, op: it.op,
                                             pesticide: it.pesticide, dose: it.dose,
                                             note: it.note, weather: it.weather,
                                             method: it.method, weatherNote: it.weatherNote) > 0 {
                        let rid = db.recordIdByUuid(it.uuid)
                        if rid > 0, !it.items.isEmpty {
                            db.replaceItems(recordId: rid, it.items.map {
                                var item = $0.asLocal
                                let pp = saveB64($0.photoB64)
                                if !pp.isEmpty { item.photoPath = pp }
                                return item
                            })
                        }
                        if it.mtime > 0 { db.setRecordMtimeByHash(it.uuid, Int64(it.mtime)) }
                        if it.sver > 0 { db.setRecordSverByHash(it.uuid, Int64(it.sver)) }
                        out.recs += 1
                    }
                    continue
                }
                // 内容指纹去重: 仅对"本机没有这个uuid"的记录生效, 防重复插入
                if db.hasContent(date: it.date, plot: it.plot, op: it.op, crop: it.crop,
                                 pesticide: it.pesticide, dose: it.dose, note: it.note,
                                 weather: it.weather, method: it.method,
                                 weatherNote: it.weatherNote, ts: it.ts) { continue }
                let rid = db.addRecord(date: it.date, plot: it.plot, crop: it.crop,
                                       op: it.op, pesticide: it.pesticide, dose: it.dose,
                                       note: it.note, hash: it.uuid, ts: it.ts,
                                       weather: it.weather, method: it.method,
                                       weatherNote: it.weatherNote)
                if rid > 0, !it.items.isEmpty {
                    db.addItems(recordId: rid, it.items.map {
                        var item = $0.asLocal
                        let pp = saveB64($0.photoB64)
                        if !pp.isEmpty { item.photoPath = pp }
                        return item
                    })
                }
                if it.mtime > 0 { db.setRecordMtimeByHash(it.uuid, Int64(it.mtime)) }
                if it.sver > 0 { db.setRecordSverByHash(it.uuid, Int64(it.sver)) }
                out.recs += 1
            }
        }
        if let leds {
            for dict in leds {
                guard let it = RemoteLedger(dict: dict) else { continue }
                if !myPhone.isEmpty, myPhone == it.device { continue }
                if it.uuid.isEmpty || db.hasLedgerUuid(it.uuid) { continue }
                let lp = saveB64(it.photoB64)  // 发票照片落本地
                db.addLedger(date: it.date, kind: it.kind, category: it.category,
                             amount: it.amount, plot: it.plot, note: it.note,
                             photo: lp.isEmpty ? nil : lp, ts: it.ts, uuid: it.uuid)
                out.leds += 1
            }
        }
        return out
    }

    // MARK: - 修改申请裁决落地 (Sync.processModDecisions:382-439)

    func processModDecisions(roles: [(role: String, code: String)]) async {
        for (role, code) in roles where role == "L" {
            do {
                let r = try await api.modReqs(code: code)
                guard (r["ok"] as? Bool) == true,
                      let reqs = r["reqs"] as? [[String: Any]] else { continue }
                for m in reqs {
                    let rid = str(m, "reqId"), st = str(m, "status")
                    let key = "moddone_" + rid
                    if rid.isEmpty || prefs.bool(forKey: key) { continue }
                    if st == "approved" {
                        let uuid = str(m, "uuid")
                        if str(m, "action") == "delete" {
                            db.deleteByUuid(uuid)
                        } else {
                            db.updateByUuid(uuid, date: str(m, "date"), crop: str(m, "crop"),
                                            op: str(m, "op"), pesticide: str(m, "pesticide"),
                                            dose: str(m, "dose"), note: str(m, "note"),
                                            method: str(m, "method"),
                                            weatherNote: str(m, "weather_note"))
                            // [sVer] 裁决行的新版本号写回: 本机再推送不会被当旧快照
                            if int(m, "sVer") > 0 {
                                db.setRecordSverByHash(uuid, Int64(int(m, "sVer")))
                            }
                            // 品项明细随裁决落地(照片保留本机文件)
                            if let its = m["items"] as? [[String: Any]] {
                                db.rewriteItemsByUuid(uuid, its.compactMap { io in
                                    RecordItem(name: str(io, "name"), dose: str(io, "dose"),
                                               note: str(io, "note"), type: str(io, "type"))
                                })
                            }
                        }
                        prefs.set(true, forKey: key)
                        await MainActor.run {
                            self.state?.syncMessage = "主管已同意\(str(m, "plot"))的记录修改, 已生效"
                        }
                    } else if st == "rejected" {
                        prefs.set(true, forKey: key)
                        await MainActor.run {
                            self.state?.syncMessage = "主管拒绝了\(str(m, "plot"))的记录修改申请"
                        }
                    }
                }
            } catch { /* 网络失败下次再落地 */ }
        }
    }

    // MARK: - 照片落本地 (saveB64: base64→本地文件, 返回路径)

    func saveB64(_ b64: String) -> String {
        guard !b64.isEmpty, let data = Data(base64Encoded: b64) else { return "" }
        let dir = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("photos", isDirectory: true)
        guard let dir else { return "" }
        let name = "p_\(abs(b64.hashValue))_\(UUID().uuidString.prefix(8)).jpg"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url.path
        } catch {
            return ""
        }
    }
}
