import Foundation

// MARK: - uuid身份规则(本地/中继/云备份三方一致, v37协议)
//
// 身份约定:
// - uuid = 创建时定死的身份证, 推送一律用本地存定的hash
// - 真实uuid无账号前缀时补"11位账号:"前缀并回写本地(与服务端正规式一致)
// - 已带任意11位前缀的一律原样——再叠前缀会造出双前缀幽灵行
// - "b:ts:plot" 等池内本地身份(遗留数据)不补前缀
// - 双前缀 "账号:rec:账号:hash" 正规化为内层 "账号:hash"(canon)

public enum UuidCanon {

    /// 字符串是否已带 11位数字+":" 前缀(任意账号前缀)
    public static func hasAccountPrefix(_ s: String) -> Bool {
        guard s.count >= 12 else { return false }
        let head = s.prefix(11)
        return head.allSatisfy { $0.isASCII && $0.isNumber }
            && s[s.index(s.startIndex, offsetBy: 11)] == ":"
    }

    /// 中继推送身份 (Sync.pushPending:550-561)
    /// 行uuid = 本地存定的hash(创建时定死身份, 修不修改都不变);
    /// hash空(远古记录)才按内容现算 "rec:fp"(列序: date|plot|op|crop|pesticide|dose|note|ts)。
    /// 只给"无任何账号前缀"的自有记录补前缀; 已带任意11位前缀的
    /// (包括授权导入的对方副本)原样推送, 中继按原行匹配就地合并。
    public static func relayUuid(hash: String, account: String,
                                 date: String, plot: String, op: String, crop: String,
                                 pesticide: String, dose: String, note: String, ts: String) -> String {
        let fp = "\(date)|\(plot)|\(op)|\(crop)|\(pesticide)|\(dose)|\(note)|\(ts)"
        var uuid = hash.isEmpty ? "rec:" + fp : hash
        if account.count == 11,
           account.allSatisfy({ $0.isASCII && $0.isNumber }),
           !hasAccountPrefix(uuid) {
            uuid = account + ":" + uuid
        }
        return uuid
    }

    /// 池推送身份 (Backup.pushPoolLocked:445-448)
    /// 与中继规则相同, 仅 "b:" 开头的遗留行不补前缀(原样)
    public static func poolUuid(_ hash: String, phone: String) -> String {
        guard !hash.isEmpty, !hash.hasPrefix("b:"),
              phone.count == 11,
              phone.allSatisfy({ $0.isASCII && $0.isNumber }),
              !hasAccountPrefix(hash) else { return hash }
        return phone + ":" + hash
    }

    /// 双前缀正规化(服务端canonUuid规则, moddecide裁决前归一):
    /// "账号:rec:账号:hash" → 内层 "账号:hash";
    /// 遗留指纹号(账号:rec:date|plot|… 7/8段)与正常号原样不变
    public static func canon(_ uuid: String) -> String {
        guard let i = uuid.range(of: ":rec:", options: .backwards) else { return uuid }
        let rest = String(uuid[i.upperBound...])
        return hasAccountPrefix(rest) ? rest : uuid
    }

    // MARK: 各类池条目身份前缀(服务端inferType: b:/rec:→record, bl:/led:→ledger, mk:→mark, dn:→note, pl:→plot)

    /// 池内本地记录身份(无账号前缀, 遗留数据): "b:ts:plot"
    public static func poolLocalRecordUuid(ts: String, plot: String) -> String {
        "b:\(ts):\(plot)"
    }

    /// 池内本地账本身份: "bl:ts:plot"
    public static func poolLocalLedgerUuid(ts: String, plot: String) -> String {
        "bl:\(ts):\(plot)"
    }

    /// 间隔标记: "mk:plot|op|date"
    public static func markUuid(plot: String, op: String, date: String) -> String {
        "mk:\(plot)|\(op)|\(date)"
    }

    /// 日常观察: "dn:ts"
    public static func dailyNoteUuid(ts: String) -> String {
        "dn:\(ts)"
    }

    /// 地块: "pl:名字"(改名=删旧建新, 天然两条池条目)
    public static func plotUuid(name: String) -> String {
        "pl:\(name)"
    }

    /// 中继账本推送身份 (Sync.pushPending:594): "led:本地id"; 副本(hash非空)不回推
    public static func relayLedgerUuid(localId: String) -> String {
        "led:\(localId)"
    }
}
