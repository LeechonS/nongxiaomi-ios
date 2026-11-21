import Foundation
import SwiftUI
import NongXiaoMiCore

// MARK: - 全局状态(对应Android端 SharedPreferences "farm" + Db)

@MainActor
final class AppState: ObservableObject {

    private let prefs = UserDefaults.standard

    // MARK: 会话(持久化)

    var isLoggedIn: Bool { !token.isEmpty }

    var phone: String {
        get { prefs.string(forKey: "auth_phone") ?? "" }
        set { prefs.set(newValue, forKey: "auth_phone") }
    }

    var token: String {
        get { prefs.string(forKey: "auth_token") ?? "" }
        set { prefs.set(newValue, forKey: "auth_token") }
    }

    /// 登录密码(本机AES加密存储, 供自动登录; 端到端备份密钥也由此派生)
    var password: String {
        get { prefs.string(forKey: "auth_pwd") ?? "" }
        set { prefs.set(newValue, forKey: "auth_pwd") }
    }

    /// 服务器地址(可被后台下发新版本地址覆盖)
    var server: String {
        get { prefs.string(forKey: "sync_server") ?? "http://111.228.62.13:8910" }
        set { prefs.set(newValue, forKey: "sync_server") }
    }

    /// 设备安装id(installUid, 首次生成)
    var installUid: String {
        get {
            if let u = prefs.string(forKey: "install_uid"), !u.isEmpty { return u }
            let u = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)
            prefs.set(String(u), forKey: "install_uid")
            return String(u)
        }
    }

    // MARK: 运行时

    @Published var syncMessage: String = ""      // 同步状态提示
    @Published var lastSyncAt: Date?
    @Published var roles: [(role: String, code: String)] = []  // B=主管 L=分管

    let db: FarmDb
    let api: ApiClient
    private(set) var syncEngine: SyncEngine?

    init() {
        let dir = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("farm", isDirectory: true)
        let path = dir?.appendingPathComponent("farm.db").path ?? "farm.db"
        do {
            let db = try FarmDb(path: path)
            self.db = db
            // 存储属性未全部初始化前不能用self的计算属性 → 本地直读UserDefaults
            let p = UserDefaults.standard
            let srv = p.string(forKey: "sync_server") ?? "http://111.228.62.13:8910"
            var uid = p.string(forKey: "install_uid") ?? ""
            if uid.isEmpty {
                uid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))
                p.set(uid, forKey: "install_uid")
            }
            let api = ApiClient(server: srv)
            api.token = p.string(forKey: "auth_token") ?? ""
            api.device = uid
            api.phone = p.string(forKey: "auth_phone") ?? ""
            self.api = api
            let engine = SyncEngine(db: db, api: api, state: self)
            self.syncEngine = engine
        } catch {
            fatalError("数据库打开失败: \(error)")
        }
    }

    // MARK: 登录/登出

    func doLogin(phone: String, password: String, invite: String) async {
        api.token = ""
        do {
            let t = try await api.login(phone: phone, password: password)
            guard !t.isEmpty else {
                syncMessage = "登录失败: 手机号或密码错误"
                return
            }
            token = t
            self.phone = phone
            self.password = password
            api.token = t
            api.phone = phone
            await refreshRoles()
        } catch {
            syncMessage = "登录失败: \(error.localizedDescription)"
        }
    }

    func doLogout() {
        token = ""
        password = ""
        phone = ""
        api.token = ""
        roles = []
    }

    /// 角色重建(对应 Sync.refreshRoles): 凭登录账号返回各组角色
    func refreshRoles() async {
        do {
            let r = try await api.myRoles()
            guard (r["ok"] as? Bool) == true,
                  let groups = r["groups"] as? [[String: Any]] else {
                return
            }
            var out: [(String, String)] = []
            for g in groups {
                let role = str(g, "role")
                let code = str(g, "code")
                if !code.isEmpty { out.append((role, code)) }
            }
            roles = out
            // 版本门(对应myroles带vers): 有变化才触发全量拉取
            if let vers = r["vers"] as? String {
                for g in out {
                    if prefs.string(forKey: "group_vers_\(g.1)") != vers {
                        prefs.set(vers, forKey: "group_vers_\(g.1)")
                    }
                }
            }
        } catch {
            // 网络失败静默, 下次tick再试
        }
    }
}

