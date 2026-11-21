import Foundation

// MARK: - 同步协议核心数据模型(纯数据, 与Android端JSON字段一一对应)

/// 农事记录(对应records表 / 组数据recs条目)
public struct FarmRecord: Equatable, Sendable {
    public var date: String
    public var plot: String
    public var crop: String
    public var op: String
    public var pesticide: String
    public var dose: String
    public var note: String
    public var weather: String
    public var method: String
    public var weatherNote: String
    /// 保存时间(精确到秒, "2026-11-17 21:53:55")
    public var ts: String
    /// 身份hash(创建时定死, 远古记录为空)
    public var uuid: String
    /// 上次比较新者胜的基准(0=无基准)
    public var mtime: Int
    /// 服务端版本号(0=无版本)
    public var sver: Int
    /// 墓碑行(删除传导)
    public var deleted: Bool
    /// 上报者账号(空=本机自录)
    public var device: String

    public init(date: String = "", plot: String = "", crop: String = "", op: String = "",
                pesticide: String = "", dose: String = "", note: String = "",
                weather: String = "", method: String = "", weatherNote: String = "",
                ts: String = "", uuid: String = "", mtime: Int = 0, sver: Int = 0,
                deleted: Bool = false, device: String = "") {
        self.date = date; self.plot = plot; self.crop = crop; self.op = op
        self.pesticide = pesticide; self.dose = dose; self.note = note
        self.weather = weather; self.method = method; self.weatherNote = weatherNote
        self.ts = ts; self.uuid = uuid; self.mtime = mtime; self.sver = sver
        self.deleted = deleted; self.device = device
    }
}

/// 账本条目(对应ledger表)
public struct LedgerEntry: Equatable, Sendable {
    public var date: String
    /// 收/支
    public var kind: String
    public var category: String
    public var amount: Double
    public var plot: String
    public var note: String
    public var ts: String
    /// 身份hash(led:本地id 或 账号正规式)
    public var uuid: String
    public var sver: Int
    public var deleted: Bool
    public var device: String

    public init(date: String = "", kind: String = "", category: String = "",
                amount: Double = 0, plot: String = "", note: String = "",
                ts: String = "", uuid: String = "", sver: Int = 0,
                deleted: Bool = false, device: String = "") {
        self.date = date; self.kind = kind; self.category = category
        self.amount = amount; self.plot = plot; self.note = note
        self.ts = ts; self.uuid = uuid; self.sver = sver
        self.deleted = deleted; self.device = device
    }
}

/// 品项明细(对应items表)
public struct RecordItem: Equatable, Sendable {
    public var name: String
    public var dose: String
    public var note: String
    public var type: String
    public var grp: String
    /// 本地文件路径(照片base64导入时转存为本地文件)
    public var photoPath: String

    public init(name: String = "", dose: String = "", note: String = "",
                type: String = "", grp: String = "", photoPath: String = "") {
        self.name = name; self.dose = dose; self.note = note
        self.type = type; self.grp = grp; self.photoPath = photoPath
    }
}

/// 池条目通用外壳(apool的items): stype区分类型, 带mtime
public struct PoolItem: Equatable, Sendable {
    public enum Stype: String, Sendable {
        case record, ledger, mark, note, plot
    }
    public var uuid: String
    public var stype: Stype
    public var mtime: Int
    public var deleted: Bool
    /// 其余字段按stype不同(以格式化字符串存放, 供签名/序列化)
    public var fields: [String: String]

    public init(uuid: String, stype: Stype, mtime: Int = 0,
                deleted: Bool = false, fields: [String: String] = [:]) {
        self.uuid = uuid; self.stype = stype; self.mtime = mtime
        self.deleted = deleted; self.fields = fields
    }
}
