import Foundation

// MARK: - 远端JSON → 本地模型 (组数据/api/read、池/apull 的解码)
//
// 解码只产出"协议层需要"的字段; 照片base64原样保留,
// 落成本地文件是App层职责(importRemote里的saveB64)。

/// 远端记录(组数据recs / 池record条目)
public struct RemoteRecord: Equatable, Sendable {
    public let uuid: String
    public let device: String
    public let sver: Int
    public let mtime: Int
    public let deleted: Bool
    public let date: String
    public let plot: String
    public let crop: String
    public let op: String
    public let pesticide: String
    public let dose: String
    public let note: String
    public let weather: String
    public let method: String
    public let weatherNote: String
    public let ts: String
    public let items: [RemoteItem]

    public init(uuid: String, device: String = "", sver: Int = 0, mtime: Int = 0,
                deleted: Bool = false, date: String = "", plot: String = "", crop: String = "",
                op: String = "", pesticide: String = "", dose: String = "", note: String = "",
                weather: String = "", method: String = "", weatherNote: String = "",
                ts: String = "", items: [RemoteItem] = []) {
        self.uuid = uuid; self.device = device; self.sver = sver; self.mtime = mtime
        self.deleted = deleted; self.date = date; self.plot = plot; self.crop = crop
        self.op = op; self.pesticide = pesticide; self.dose = dose; self.note = note
        self.weather = weather; self.method = method; self.weatherNote = weatherNote
        self.ts = ts; self.items = items
    }

    /// 转本地模型(合并裁决+落库用; 照片待App层转存后补items)
    public var asLocal: FarmRecord {
        FarmRecord(date: date, plot: plot, crop: crop, op: op,
                   pesticide: pesticide, dose: dose, note: note,
                   weather: weather, method: method, weatherNote: weatherNote,
                   ts: ts, uuid: uuid, mtime: mtime, sver: sver,
                   deleted: deleted, device: device)
    }

    /// 池条目(同结构, kind字段服务端已删除防撞名)
    public init?(poolDict: [String: Any]) {
        guard let uuid = poolDict["uuid"] as? String, !uuid.isEmpty else { return nil }
        self.init(uuid: uuid,
                  device: str(poolDict, "device"),
                  sver: int(poolDict, "sVer"),
                  mtime: int(poolDict, "mtime"),
                  deleted: bool(poolDict, "deleted"),
                  date: str(poolDict, "date"), plot: str(poolDict, "plot"),
                  crop: str(poolDict, "crop"), op: str(poolDict, "op"),
                  pesticide: str(poolDict, "pesticide"), dose: str(poolDict, "dose"),
                  note: str(poolDict, "note"), weather: str(poolDict, "weather"),
                  method: str(poolDict, "method"), weatherNote: str(poolDict, "weather_note"),
                  ts: str(poolDict, "ts"),
                  items: RemoteItem.fromArray(poolDict["items"] as? [[String: Any]]))
    }

    /// 组数据/api/read 记录条目
    public init?(dict: [String: Any]) {
        self.init(poolDict: dict)
    }
}

/// 远端品项明细
public struct RemoteItem: Equatable, Sendable {
    public let name: String
    public let dose: String
    public let note: String
    public let type: String
    public let grp: String
    /// 照片base64(App层转存本地文件)
    public let photoB64: String

    public init(name: String = "", dose: String = "", note: String = "",
                type: String = "", grp: String = "", photoB64: String = "") {
        self.name = name; self.dose = dose; self.note = note
        self.type = type; self.grp = grp; self.photoB64 = photoB64
    }

    public var asLocal: RecordItem {
        RecordItem(name: name, dose: dose, note: note, type: type, grp: grp)
    }

    static func fromArray(_ arr: [[String: Any]]?) -> [RemoteItem] {
        (arr ?? []).compactMap { d in
            RemoteItem(name: str(d, "name"), dose: str(d, "dose"), note: str(d, "note"),
                       type: str(d, "type"), grp: str(d, "grp"),
                       photoB64: str(d, "photo_b64"))
        }
    }
}

/// 远端账本(组数据leds / 池ledger条目)
public struct RemoteLedger: Equatable, Sendable {
    public let uuid: String
    public let device: String
    public let sver: Int
    public let mtime: Int
    public let deleted: Bool
    public let date: String
    /// 收支方向(池条目里服务端改名stype, 组数据里就是kind)
    public let kind: String
    public let category: String
    public let amount: Double
    public let plot: String
    public let note: String
    public let ts: String
    public let photoB64: String

    public init(uuid: String, device: String = "", sver: Int = 0, mtime: Int = 0,
                deleted: Bool = false, date: String = "", kind: String = "",
                category: String = "", amount: Double = 0, plot: String = "",
                note: String = "", ts: String = "", photoB64: String = "") {
        self.uuid = uuid; self.device = device; self.sver = sver; self.mtime = mtime
        self.deleted = deleted; self.date = date; self.kind = kind
        self.category = category; self.amount = amount; self.plot = plot
        self.note = note; self.ts = ts; self.photoB64 = photoB64
    }

    public var asLocal: LedgerEntry {
        LedgerEntry(date: date, kind: kind, category: category, amount: amount,
                    plot: plot, note: note, ts: ts, uuid: uuid, sver: sver,
                    deleted: deleted, device: device)
    }

    public init?(dict: [String: Any]) {
        guard let uuid = dict["uuid"] as? String, !uuid.isEmpty else { return nil }
        self.init(uuid: uuid,
                  device: str(dict, "device"),
                  sver: int(dict, "sVer"),
                  mtime: int(dict, "mtime"),
                  deleted: bool(dict, "deleted"),
                  date: str(dict, "date"),
                  kind: str(dict, "kind"),
                  category: str(dict, "category"),
                  amount: dict["amount"] as? Double ?? 0,
                  plot: str(dict, "plot"),
                  note: str(dict, "note"),
                  ts: str(dict, "ts"),
                  photoB64: str(dict, "photo_b64"))
    }
}

// MARK: - JSON取值小工具(容错: 缺字段=空串/0/false, 与Java optXxx语义一致)

@inline(__always)
public func str(_ d: [String: Any], _ k: String) -> String {
    (d[k] as? String) ?? ""
}

@inline(__always)
public func int(_ d: [String: Any], _ k: String) -> Int {
    if let n = d[k] as? Int { return n }
    if let n = d[k] as? Double { return Int(n) }
    if let s = d[k] as? String, let n = Int(s) { return n }
    return 0
}

@inline(__always)
public func bool(_ d: [String: Any], _ k: String) -> Bool {
    (d[k] as? Bool) ?? false
}
