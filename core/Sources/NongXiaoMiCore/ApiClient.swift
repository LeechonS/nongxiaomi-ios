import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - API客户端(端点目录对齐 farm_sync/server.js)
//
// 默认服务器地址与Android端一致; 全部走 token 鉴权,
// 403/被踢(checkKicked)的处理在App层同步引擎里做。

public struct ApiError: Error, Equatable, CustomStringConvertible {
    public let code: Int          // 0=传输异常, 否则HTTP状态码
    public let message: String
    public var description: String { "API错误[\(code)]: \(message)" }
}

public final class ApiClient {

    /// 服务器地址(与Android端 SharedPreferences "sync_server" 同默认值)
    public var server: String
    /// 登录token
    public var token: String = ""
    /// 设备安装id(installUid)
    public var device: String = ""

    public init(server: String = "http://111.228.62.13:8910") {
        self.server = server
    }

    // MARK: - 通用请求

    public func get(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        var comps = URLComponents(string: server + path) ?? URLComponents()
        var items: [URLQueryItem] = []
        for (k, v) in query {
            if !v.isEmpty { items.append(URLQueryItem(name: k, value: v)) }
        }
        if !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else { throw ApiError(code: 0, message: "URL无效") }
        return try await raw(url, method: "GET", body: nil)
    }

    public func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: server + path) ?? URL(string: server)!
        return try await raw(url, method: "POST", body: body)
    }

    private func raw(_ url: URL, method: String, body: [String: Any]?) async throws -> [String: Any] {
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body, let data = try? JSONSerialization.data(withJSONObject: body) {
            req.httpBody = data
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ApiError(code: 0, message: String(describing: error))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        // Android端语义: 非2xx抛异常(带响应体); 这里统一抛ApiError
        if !(200..<300).contains(status) {
            throw ApiError(code: status, message: json["err"] as? String ?? text)
        }
        return json
    }

    // MARK: - 账号

    /// 登录 → token
    @discardableResult
    public func login(phone: String, password: String) async throws -> String {
        let r = try await post("/api/login", body: ["phone": phone, "password": password])
        return r["token"] as? String ?? ""
    }

    /// 修改密码
    public func changePwd(old: String, new: String) async throws {
        _ = try await post("/api/changepwd", body: ["token": token, "old": old, "new": new])
    }

    // MARK: - 组(主管建组/分管加组)

    /// 建组(当老板) → 分享码
    @discardableResult
    public func createGroup(name: String, plots: [String]) async throws -> String {
        let r = try await post("/api/group", body: ["token": token, "name": name, "plots": plots])
        return r["code"] as? String ?? ""
    }

    /// 输码加入(登录账号=分管)
    public func joinGroup(code: String) async throws {
        _ = try await post("/api/join", body: ["code": code, "token": token])
    }

    /// 角色重建: 凭登录账号返回其在各组的角色(B=主管/L=分管)
    public func myRoles() async throws -> [String: Any] {
        try await get("/api/myroles", query: ["device": device])
    }

    /// 本组授权类型(主管=全量)
    public func myTypes(code: String) async throws -> [String: Any] {
        try await get("/api/mytypes", query: ["code": code, "device": device])
    }

    /// 授权/收回(按类型: records/ledger, 空=收回)
    public func auth(code: String, member: String, types: [String]) async throws {
        _ = try await post("/api/auth", body: ["code": code, "token": token, "member": member,
                                               "types": types])
    }

    /// 删组(仅建组者)
    public func deleteGroup(code: String) async throws {
        _ = try await post("/api/groupdel", body: ["code": code, "token": token])
    }

    // MARK: - 组数据同步(分管→组)

    /// 推送组数据 → pushed数 + 各uuid的新sVer(写回本地)
    @discardableResult
    public func push(code: String, records: [[String: Any]], ledger: [[String: Any]])
        async throws -> (pushed: Int, sVers: [String: Int]) {
        let r = try await post("/api/push", body: [
            "code": code, "device": device, "token": token,
            "records": records, "ledger": ledger])
        var sVers: [String: Int] = [:]
        if let sv = r["sVers"] as? [String: Any] {
            for (k, v) in sv {
                sVers[k] = (v as? Int) ?? Int((v as? Double) ?? 0)
            }
        }
        return ((r["pushed"] as? Int) ?? 0, sVers)
    }

    /// 读组数据(want=records/ledger), 仅被授权时可用
    public func read(code: String, want: String) async throws -> [String: Any] {
        try await get("/api/read", query: ["code": code, "device": device, "want": want])
    }

    /// 主管: 各地块未读条数
    public func newCount(code: String) async throws -> [String: Any] {
        try await get("/api/newcount", query: ["code": code, "device": device])
    }

    /// 汇总: 仅建组者可拉
    public func summary(code: String) async throws -> [String: Any] {
        try await get("/api/summary", query: ["code": code])
    }

    // MARK: - 修改申请(分管申请 → 主管裁决)

    /// 提交修改/删除申请(本地不生效, 等裁决)
    public func submitModRequest(code: String, uuid: String, action: String,
                                 fields: [String: Any]) async throws {
        _ = try await post("/api/modreq", body: [
            "code": code, "token": token, "uuid": uuid,
            "action": action, "fields": fields])
    }

    /// 拉修改申请: 建组者=全部待审; 队长=自己的(含裁决结果)
    public func modReqs(code: String) async throws -> [String: Any] {
        try await get("/api/modreqs", query: ["code": code])
    }

    /// 裁决: approve/reject
    public func modDecide(code: String, uuid: String, decision: String) async throws {
        _ = try await post("/api/moddecide", body: [
            "code": code, "token": token, "uuid": uuid, "decision": decision])
    }

    // MARK: - 账号池(同账号多设备)

    /// 推池 → adopted列表(只登记被采纳的签名)
    @discardableResult
    public func apool(items: [[String: Any]]) async throws -> [String] {
        let r = try await post("/api/apool", body: [
            "phone": phone, "token": token, "device": device, "items": items])
        return (r["adopted"] as? [String]) ?? []
    }

    /// 拉本账号池全量
    public func apull() async throws -> [String: Any] {
        try await get("/api/apull")
    }

    /// 长轮询池版本(最多挂25秒, 有变化立刻返回)
    public func awaitPoolVersion(since: String) async throws -> [String: Any] {
        try await get("/api/aver", query: ["since": since])
    }

    /// 登录手机号(apool需要; 与Android端 auth_phone 一致)
    public var phone: String = ""

    // MARK: - 云备份(分级隐私: pub公开桶 + enc端到端加密桶)

    public func backup(pub: [String: Any], enc: [String: Any]) async throws {
        _ = try await post("/api/backup", body: ["token": token, "pub": pub, "enc": enc])
    }

    public func restore() async throws -> [String: Any] {
        try await get("/api/restore")
    }

    // MARK: - 工具端点

    /// OCR拍照识别(照片base64, 服务端调视觉模型)
    public func ocr(imageB64: String) async throws -> [String: Any] {
        try await post("/api/ocr", body: ["image_b64": imageB64])
    }

    public func weather(lat: Double, lon: Double) async throws -> [String: Any] {
        try await get("/api/weather", query: [
            "lat": String(format: "%.4f", lat), "lon": String(format: "%.4f", lon)])
    }

    /// App版本检查
    public func appVersion(current: Int) async throws -> [String: Any] {
        try await get("/api/version", query: ["v": String(current)])
    }

    public func ping() async -> Bool {
        (try? await get("/api/ping")) != nil
    }
}

// 兼容 sVers 里数值可能是字符串/整数的取值
private func int(_ d: [String: Any], _ k: String) -> Int? {
    if let n = d[k] as? Int { return n }
    if let n = d[k] as? Double { return Int(n) }
    return nil
}
