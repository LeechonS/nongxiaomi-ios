import Foundation
import NongXiaoMiCore

// MARK: - 同步引擎(续): 推送
//
// pushGroup  = Sync.pushPending:447-638 移植(分管→组, 含授权闸门/签名去重/sVer写回)
// pushPool   = Backup.pushPoolLocked:432-685 移植(同账号多设备池, 只上传)

extension SyncEngine {

    // MARK: - 组数据推送 (pushPending)

    func pushGroup() async throws {
        let roles = try await getRoles()
        for (role, code) in roles where role == "L" {
            do {
                try await pushOneGroup(code: code)
            } catch { /* 单组失败不影响其它组, 下次tick再推 */ }
        }
    }

    private func pushOneGroup(code: String) async throws {
        await processModDecisions(roles: [(role: "L", code: code)])
        // 授权闸门: mytypes查本组授权类型
        let mtR: [String: Any]
        do {
            mtR = try await api.myTypes(code: code)
        } catch let e as ApiError where e.message.contains("分享码不存在") {
            // 明确信号: 主管已删组 → 清本地角色缓存+记录账本
            clearLocalForGroup(code)
            await MainActor.run {
                self.state?.syncMessage = "组\(code)已被主管删除，本地记录与账本已全部清除"
            }
            return
        } catch {
            return // 网络失败照旧静默跳过, 绝不误删
        }
        var canPush = false, hasView = false
        if (mtR["ok"] as? Bool) == true, let types = mtR["types"] as? [String] {
            for t in types {
                if t == "push" { canPush = true }
                if t == "records" || t == "ledger" { hasView = true }
            }
        }
        if hasView {
            // 被授权查看历史: 主管数据直接导入本地
            for want in ["records", "ledger"] {
                if let r = try? await api.read(code: code, want: want),
                   (r["ok"] as? Bool) == true {
                    _ = await importRemote(recs: r["records"] as? [[String: Any]],
                                           leds: r["ledger"] as? [[String: Any]])
                }
            }
            prefs.set(true, forKey: "sync_hist_" + code)
        } else if (mtR["ok"] as? Bool) == true,
                  prefs.bool(forKey: "sync_hist_" + code) {
            // 明确撤回(服务端确认types里已无records): 本地历史全清; 请求失败时绝不清
            db.clearAllRecordsLedger()
            prefs.removeObject(forKey: "push_rec_" + code)
            prefs.removeObject(forKey: "push_led_" + code)
            await MainActor.run {
                self.state?.syncMessage = "组\(code)授权已撤回，本地记录与账本已全部清除"
            }
            return
        }
        guard canPush else { return }

        // 授权地块过滤(主管旧组没存地块=不过滤)
        let plots = (prefs.string(forKey: "sync_plots_" + code) ?? "").split(separator: ";")
        let plotSet = plots.isEmpty ? nil : Set(plots.map { $0.description })

        // 水位自愈: 本机最大id小于水位(重装/恢复/清库后id倒退) → 水位归零
        let allRecs = db.listRecords()
        let maxRecId = allRecs.map { $0.id }.max() ?? 0
        var wmRec = prefs.integer(forKey: "push_rec_" + code)
        if Int64(wmRec) > maxRecId { wmRec = 0 }
        let allLeds = db.listLedger()
        let maxLedId = allLeds.map { $0.id }.max() ?? 0
        var wmLed = prefs.integer(forKey: "push_led_" + code)
        if Int64(wmLed) > maxLedId { wmLed = 0 }

        // 记录全量扫+按mtime签名增量(水位只看id, 编辑过的老行靠签名重推)
        let relaySigs = Set(
            (prefs.string(forKey: "relay_sig_" + code) ?? "")
                .components(separatedBy: "\n").filter { !$0.isEmpty })
        var newSigs = Set<String>()
        let myAcc = api.phone
        var recs: [[String: Any]] = []
        var maxRec = wmRec
        for r in allRecs {
            if let plotSet, !plotSet.contains(r.plot) { continue }
            // 行uuid = 本地存定的hash(创建时定死身份, 修不修改都不变):
            // hash空(远古记录)才按内容现算; 不带账号前缀的补成正规式并回写
            let uuid = UuidCanon.relayUuid(
                hash: r.hash, account: myAcc,
                date: r.date, plot: r.plot, op: r.op, crop: r.crop,
                pesticide: r.pesticide, dose: r.dose, note: r.note, ts: r.ts)
            if uuid != r.hash {
                db.setHashById(r.id, uuid) // 回写: 此后各端同一身份
            }
            let sig = "\(uuid)|\(r.mtime)|\(r.sver)"
            newSigs.insert(sig)
            if relaySigs.contains(sig) { continue } // 自上次推送后没变过
            var ro: [String: Any] = [
                "uuid": uuid, "id": r.id, "plot": r.plot, "date": r.date,
                "crop": r.crop, "op": r.op, "pesticide": r.pesticide,
                "dose": r.dose, "note": r.note, "ts": r.ts, "method": r.method,
                "weather_note": r.weatherNote, "weather": r.weather,
                "sVer": r.sver, // [sVer] 推送带版本号: 服务端据此拒收旧快照
            ]
            // 品项明细连照片一起推, 授权端才能看到完整记录
            let items = db.listItems(recordId: r.id).map { it -> [String: Any] in
                var io: [String: Any] = [
                    "name": it.name, "dose": it.dose, "note": it.note,
                    "type": it.type, "grp": it.grp,
                ]
                if let b64 = photoB64(it.photoPath) { io["photo_b64"] = b64 }
                return io
            }
            if !items.isEmpty { ro["items"] = items }
            recs.append(ro)
            maxRec = Int(r.id)
        }

        // 账本: 副本不回推(hash非空=授权导入的)
        var leds: [[String: Any]] = []
        var maxLed = wmLed
        for l in allLeds where l.id > Int64(wmLed) {
            if let plotSet, !plotSet.contains(l.plot) { continue }
            if !l.uuid.isEmpty { continue }
            var lo: [String: Any] = [
                "uuid": UuidCanon.relayLedgerUuid(localId: String(l.id)),
                "id": l.id, "plot": l.plot, "date": l.date, "kind": l.kind,
                "category": l.category, "amount": l.amount, "note": l.note,
                "ts": l.ts, "sVer": l.sver,
            ]
            if !l.photo.isEmpty, let b64 = photoB64(l.photo) { lo["photo_b64"] = b64 }
            leds.append(lo)
            maxLed = Int(l.id)
        }

        if recs.isEmpty && leds.isEmpty {
            prefs.set(maxRec, forKey: "push_rec_" + code)
            prefs.set(maxLed, forKey: "push_led_" + code)
            return
        }

        // 推送 + [sVer] 服务端版本号写回本地(本次真正更新/新建的行)
        let (pushed, sVers) = try await api.push(code: code, records: recs, ledger: leds)
        for (u, sv) in sVers where sv > 0 {
            if u.hasPrefix("led:") {
                db.setLedgerSver(u, Int64(sv))
            } else {
                db.setRecordSverByHash(u, Int64(sv))
            }
        }
        prefs.set(maxRec, forKey: "push_rec_" + code)
        prefs.set(maxLed, forKey: "push_led_" + code)
        prefs.set(newSigs.joined(separator: "\n"), forKey: "relay_sig_" + code)
        _ = pushed
    }

    /// 删组时清本地(角色缓存+该组缓存; 角色清理由AppState刷新)
    private func clearLocalForGroup(_ code: String) {
        prefs.removeObject(forKey: "sync_plots_" + code)
        prefs.removeObject(forKey: "sync_hist_" + code)
        prefs.removeObject(forKey: "push_rec_" + code)
        prefs.removeObject(forKey: "push_led_" + code)
        prefs.removeObject(forKey: "relay_sig_" + code)
        prefs.removeObject(forKey: "groupdata_" + code)
        db.clearAllRecordsLedger()
    }

    // MARK: - 账号池推送 (pushPoolLocked)

    func pushPool() async throws {
        let phone = api.phone
        let token = api.token
        guard !phone.isEmpty, !token.isEmpty else { return }

        // 本机数据自建(与快照同构, 只推池内没有的)
        let recs: [[String: Any]] = db.listRecords().map { r in
            let uu0 = r.hash.isEmpty
                ? UuidCanon.poolLocalRecordUuid(ts: r.ts, plot: r.plot)
                : UuidCanon.poolUuid(r.hash, phone: phone)
            if uu0 != r.hash, !r.hash.isEmpty {
                db.setHashById(r.id, uu0) // [身份收敛] 补账号前缀并回写本地hash
            }
            var ro: [String: Any] = [
                "device": api.device, "uuid": uu0, "plot": r.plot, "date": r.date,
                "crop": r.crop, "op": r.op, "pesticide": r.pesticide, "dose": r.dose,
                "note": r.note, "ts": r.ts, "method": r.method,
                "weather_note": r.weatherNote, "weather": r.weather,
                "sVer": r.sver,
            ]
            let items = db.listItems(recordId: r.id).map { it -> [String: Any] in
                var io: [String: Any] = [
                    "name": it.name, "dose": it.dose, "note": it.note,
                    "type": it.type,
                ]
                if let b64 = photoB64(it.photoPath) { io["photo_b64"] = b64 }
                return io
            }
            if !items.isEmpty { ro["items"] = items }
            return ro
        }
        let leds: [[String: Any]] = db.listLedger().map { l in
            let uu = l.uuid.isEmpty
                ? UuidCanon.poolLocalLedgerUuid(ts: l.ts, plot: l.plot)
                : l.uuid
            var lo: [String: Any] = [
                "device": api.device, "uuid": uu, "plot": l.plot, "date": l.date,
                "kind": l.kind, "category": l.category,
                "amount": l.amount, // JSON里是数字; 只有签名用Java形态(见sigFields)
                "note": l.note, "ts": l.ts,
            ]
            if !l.photo.isEmpty, let b64 = photoB64(l.photo) { lo["photo_b64"] = b64 }
            return lo
        }

        let pooled = Set(prefs.stringArray(forKey: "pool_pushed") ?? [])
        let pushedSig = Set(prefs.stringArray(forKey: "pushed_sig") ?? [])
        var newly = Set<String>()
        var newlySig = Set<String>()

        func filterPush(_ arr: [[String: Any]], isNoteOrPlot: Bool) -> ([[String: Any]], [String: String]) {
            var out: [[String: Any]] = []
            var sigByUu: [String: String] = [:]
            for var it in arr {
                let uu = str(it, "uuid")
                // 签名含不含照片: 记录/账本排除照片b64, 观察/地块含照片(加换照片=编辑)
                let keep = isNoteOrPlot
                let sig = PoolSig.sig(sigFields(of: it, keepPhotoB64s: keep),
                                      keepPhotoB64s: keep)
                let pooledHas = pooled.contains(uu)
                let everSigned = pushedSig.contains { $0.hasPrefix(uu + "|") }
                if uu.isEmpty || (pooledHas && (!everSigned || pushedSig.contains(uu + "|" + sig))) {
                    if pooledHas { newlySig.insert(uu + "|" + sig) } // 首次登记签名不重推
                    continue
                }
                newlySig.insert(uu + "|" + sig)
                if !pooledHas { newly.insert(uu) } // 新增才登记pool_pushed; 编辑重推走签名
                sigByUu[uu] = uu + "|" + sig
                out.append(it)
            }
            return (out, sigByUu)
        }

        let (pr, sigRecs) = filterPush(recs, isNoteOrPlot: false)
        let (pl, sigLeds) = filterPush(leds, isNoteOrPlot: false)

        // 间隔标记(身份=内容推导uuid, 天然去重)
        let recIdToUuid = Dictionary(uniqueKeysWithValues: db.listRecords().map {
            ($0.id, $0.hash.isEmpty
                ? UuidCanon.poolLocalRecordUuid(ts: $0.ts, plot: $0.plot)
                : UuidCanon.poolUuid($0.hash, phone: phone))
        })
        var mks: [[String: Any]] = []
        for m in db.listMarks() where !pooled.contains(UuidCanon.markUuid(plot: m.plot, op: m.op, date: m.date)) {
            let uu = UuidCanon.markUuid(plot: m.plot, op: m.op, date: m.date)
            var mo: [String: Any] = ["uuid": uu, "plot": m.plot, "op": m.op, "date": m.date]
            if m.recordId != "0", let ru = recIdToUuid[Int64(m.recordId)] {
                mo["rec_uuid"] = ru // 关联记录的uuid, 对端回链用
            }
            mks.append(mo)
            newly.insert(uu)
        }

        // 日常观察(签名含照片)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var nts: [[String: Any]] = []
        var sigNotes: [String: String] = [:]
        for n in db.listDailyNotes() where !n.ts.isEmpty {
            let uu = UuidCanon.dailyNoteUuid(ts: n.ts)
            var no: [String: Any] = [
                "uuid": uu, "date": n.date, "content": n.content, "ts": n.ts,
                "weather": n.weather, "gps": n.gps, "star": n.star,
            ]
            if !n.photos.isEmpty {
                var pbs: [String] = []
                for p in n.photos.split(separator: ";") {
                    if let b64 = photoB64(String(p)) { pbs.append(b64) }
                }
                if !pbs.isEmpty { no["photo_b64s"] = pbs }
            }
            let sig = PoolSig.sig(sigFields(of: no, keepPhotoB64s: true), keepPhotoB64s: true)
            let pooledHas = pooled.contains(uu)
            if pooledHas && pushedSig.contains(uu + "|" + sig) { continue }
            newlySig.insert(uu + "|" + sig)
            sigNotes[uu] = uu + "|" + sig
            if !pooledHas { newly.insert(uu) }
            no["mtime"] = now
            nts.append(no)
        }

        // 地块(身份=名字, 改名=删旧建新; 签名含圈定图)
        var pls: [[String: Any]] = []
        var sigPlots: [String: String] = [:]
        for p in db.listPlots() where !p.name.isEmpty {
            let uu = UuidCanon.plotUuid(name: p.name)
            var po: [String: Any] = [
                "uuid": uu, "name": p.name, "polygon": p.polygon, "center": p.center,
                "area": p.area,
            ]
            if !p.thumb.isEmpty, let b64 = photoB64(p.thumb) { po["thumb_b64"] = b64 }
            let sig = PoolSig.sig(sigFields(of: po, keepPhotoB64s: true), keepPhotoB64s: true)
            let pooledHas = pooled.contains(uu)
            if pooledHas && pushedSig.contains(uu + "|" + sig) { continue }
            newlySig.insert(uu + "|" + sig)
            sigPlots[uu] = uu + "|" + sig
            if !pooledHas { newly.insert(uu) }
            po["mtime"] = now
            pls.append(po)
        }

        // 合并成通用items桶: 每条带stype类型标签+mtime, 云端按mtime新者胜
        var items: [[String: Any]] = []
        for var it in pr { it["stype"] = "record"; it["mtime"] = now; items.append(it) }
        for var it in pl { it["stype"] = "ledger"; it["mtime"] = now; items.append(it) }
        for var it in mks { it["stype"] = "mark"; items.append(it) }
        for var it in nts { it["stype"] = "note"; items.append(it) }
        for var it in pls { it["stype"] = "plot"; items.append(it) }

        // 取走墓碑(本地删除传播): 推送成功才算数, 失败重挂下次再推
        let tombs = db.takeTombstones()
        for t in tombs {
            var to: [String: Any] = ["uuid": t.uuid, "stype": t.kind,
                                     "deleted": true, "mtime": now]
            if t.kind == "mark", t.uuid.hasPrefix("mk:") {
                // 带上身份字段, 对端按plot|op|date找本地标记
                let pp = String(t.uuid.dropFirst(3)).split(separator: "|").map { String($0) }
                if pp.count == 3 {
                    to["plot"] = pp[0]; to["op"] = pp[1]; to["date"] = pp[2]
                }
            }
            items.append(to)
        }

        if items.isEmpty {
            if !newlySig.isEmpty { // 没有要推的: 但首次迁移的签名登记仍要落盘
                var ns0 = Set(pushedSig); ns0.formUnion(newlySig)
                prefs.set(Array(ns0), forKey: "pushed_sig")
            }
            return
        }

        do {
            let adopted = try await api.apool(items: items)
            let acked = true
            var ns = Set(pooled)
            var nsig = Set(pushedSig)
            if !acked {
                ns.formUnion(newly)
                nsig.formUnion(newlySig)
            } else {
                // 只登记服务端真正采纳(adopted)的签名: 被拒条目(如版本旧)下次自动重推
                let adoptedSet = Set(adopted)
                for it in items where adoptedSet.contains(str(it, "uuid")) {
                    let u2 = str(it, "uuid")
                    ns.insert(u2)
                    let s2 = sigRecs[u2] ?? sigLeds[u2] ?? sigNotes[u2] ?? sigPlots[u2]
                    if let s2 { nsig.insert(s2) }
                }
            }
            prefs.set(Array(ns), forKey: "pool_pushed")
            prefs.set(Array(nsig), forKey: "pushed_sig")
        } catch {
            for t in tombs { db.addTombstone(kind: t.kind, uuid: t.uuid) } // 重挂墓碑
            throw error
        }
    }

    // MARK: - 辅助

    /// 本地照片文件 → 压缩base64(各端重压形态不同, 协议已排除照片b64做指纹)
    private func photoB64(_ path: String) -> String? {
        guard !path.isEmpty, let data = compressPhoto(path) else { return nil }
        return data.base64EncodedString()
    }

    /// sigOf字段: 全部键值转字符串(数字用Java形态), 排除项由PoolSig.sig处理
    private func sigFields(of dict: [String: Any], keepPhotoB64s: Bool) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in dict {
            if k == "device" || k == "mtime" || k == "stype" || k == "photo_b64" { continue }
            if !keepPhotoB64s && (k == "photo_b64s" || k == "photo") { continue }
            switch v {
            case let s as String:
                out[k] = s
            case let n as Int:
                out[k] = String(n)
            case let n as Double:
                out[k] = JavaNumber.doubleString(n)
            case let b as Bool:
                out[k] = b ? "true" : "false"
            case let a as [String]:
                // Java JSONArray.toString形态: ["a","b"] (带方括号)
                out[k] = "[" + a.map { "\"\($0)\"" }.joined(separator: ",") + "]"
            default:
                break
            }
        }
        return out
    }
}
