import Foundation

// MARK: - 内容指纹(去重口径, 与Android端逐字段对齐)

public enum ContentKey {

    /// 10字段内容指纹 (Sync.contentFp:261-270, 本地dedupe用同口径):
    /// date|plot|op|crop|pesticide|dose|note|weather|method|weatherNote
    /// 注意: 本地去重不含ts
    public static func recordFingerprint(_ r: FarmRecord) -> String {
        [r.date, r.plot, r.op, r.crop, r.pesticide, r.dose, r.note,
         r.weather, r.method, r.weatherNote].joined(separator: "|")
    }

    /// 11字段导入去重键 (Db.hasContent:648): 10字段 + 保存时间ts
    /// 纯照片记录(字段全空)靠保存时间相互区分不再撞车,
    /// 同一条记录跨端ts一致仍可去重
    public static func recordContentKey(_ r: FarmRecord) -> String {
        recordFingerprint(r) + "|" + r.ts
    }

    /// 账本去重键 (Sync.dedupeLocal:362-370): date|kind|category|amount|plot|note
    /// amount按Java Double.toString形态(与Android端完全一致, 见JavaNumber)
    public static func ledgerFingerprint(_ l: LedgerEntry) -> String {
        [l.date, l.kind, l.category, JavaNumber.doubleString(l.amount), l.plot, l.note]
            .joined(separator: "|")
    }
}
