import Foundation
import SQLite3C  // 系统sqlite3(Termux/Apple通用; 见Sources/SQLite3C/module.modulemap)

// C宏 SQLITE_TRANSIENT = ((sqlite3_destructor_type)-1), Swift不自动导入, 手动构造。
// 必须用它绑定 withCString 的临时缓冲: nil(=SQLITE_STATIC)会让sqlite不拷贝字符串、
// 直接持有指针, 而 withCString 的缓冲在闭包结束后即被释放 → 悬垂指针 → step时读到
// 脏内存(值被清空/变BEL乱码), 甚至破坏堆导致后续查询行为错乱。SQLITE_TRANSIENT让
// sqlite在绑定时把字符串拷进自己的内存, 临时缓冲释放也安全。
fileprivate let SQLITE_TRANSIENT: sqlite3_destructor_type =
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - 本地数据库(schema与Android端 Db.java v19 完全一致)
//
// iOS是新装库: 直接建完整v19表(与Android"新装库直接建完整表"同路径)。
// 表结构必须逐列一致——两端数据经同一云端往返, 任何列差异都会破坏同步。

public enum FarmDbError: Error, Equatable {
    case openFailed
    case execFailed(String)
}

/// 农事记录行(列序对齐 Java listRecordRows:
/// [0]id [1]plot [2]date [3]crop [4]op [5]pesticide [6]dose [7]note
/// [8]ts [9]method [10]weather_note [11]weather [12]hash [13]mtime [14]sver)
public struct RecordRow: Equatable, Sendable {
    public let id: Int64
    public let plot: String
    public let date: String
    public let crop: String
    public let op: String
    public let pesticide: String
    public let dose: String
    public let note: String
    public let ts: String
    public let method: String
    public let weatherNote: String
    public let weather: String
    public let hash: String
    public let mtime: Int64
    public let sver: Int64

    public var farmRecord: FarmRecord {
        FarmRecord(date: date, plot: plot, crop: crop, op: op,
                   pesticide: pesticide, dose: dose, note: note,
                   weather: weather, method: method, weatherNote: weatherNote,
                   ts: ts, uuid: hash, mtime: Int(mtime), sver: Int(sver))
    }
}

/// 账本行(列序对齐 Java listLedgerRows:
/// [0]id [1]plot [2]date [3]kind [4]category [5]amount [6]note [7]ts [8]photo [9]uuid [10]sver)
public struct LedgerRow: Equatable, Sendable {
    public let id: Int64
    public let plot: String
    public let date: String
    public let kind: String
    public let category: String
    public let amount: Double
    public let note: String
    public let ts: String
    public let photo: String
    public let uuid: String
    public let sver: Int64
}

public final class FarmDb {

    public static let schemaVersion = 19

    /// v19完整建表SQL(与 Db.java onCreate 逐条一致)
    public static let schemaSQL: [String] = [
        "CREATE TABLE IF NOT EXISTS records(id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "date TEXT NOT NULL, plot TEXT, crop TEXT, op TEXT, pesticide TEXT," +
        "dose TEXT, note TEXT, photo TEXT, gps TEXT, hash TEXT, ts TEXT, weather TEXT," +
        " method TEXT, weather_note TEXT, mtime INTEGER DEFAULT 0," +
        " sver INTEGER DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS plots(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE," +
        "polygon TEXT, area REAL, thumb TEXT, center TEXT)",
        "CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "record_id INTEGER NOT NULL, name TEXT, dose TEXT, note TEXT, photo TEXT," +
        " type TEXT DEFAULT '', grp TEXT DEFAULT '')",
        "CREATE TABLE IF NOT EXISTS dailynotes(id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "date TEXT NOT NULL, content TEXT, photos TEXT, ts TEXT," +
        " weather TEXT, gps TEXT, star INTEGER DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS ledger(id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "date TEXT NOT NULL, kind TEXT NOT NULL, category TEXT, amount REAL NOT NULL," +
        " plot TEXT, note TEXT, photo TEXT, ts TEXT, uuid TEXT DEFAULT ''," +
        " sver INTEGER DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS marks(id INTEGER PRIMARY KEY AUTOINCREMENT," +
        "plot TEXT NOT NULL, op TEXT NOT NULL, date TEXT NOT NULL, ts TEXT," +
        " record_id INTEGER DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS sync_tombstones(" +
        "kind TEXT, uuid TEXT, ts INTEGER, UNIQUE(kind,uuid))",
    ]

    private var handle: OpaquePointer?

    public init(path: String) throws {
        // ":memory:" 供测试; 应用内传文件路径
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            if let h = handle { sqlite3_close(h) }
            throw FarmDbError.openFailed
        }
        _ = run("PRAGMA journal_mode=WAL") // 与Android端一致, 减少同步写入竞争
        try prepare()
    }

    deinit {
        if let h = handle { sqlite3_close(h) }
    }

    private func prepare() throws {
        for sql in Self.schemaSQL {
            try exec(sql)
        }
        _ = run("PRAGMA user_version=\(Self.schemaVersion)")
    }

    // MARK: - 基础执行

    /// 统一prepare: Linux的裸C签名要求5参(pzTail), Apple有overlay可4参——
    /// 这里一律走5参裸签名, 双平台通用
    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        return sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK ? stmt : nil
    }

    @discardableResult
    private func exec(_ sql: String, params: [Any?] = []) throws -> Int64 {
        guard let stmt = prepare(sql) else {
            throw FarmDbError.execFailed(sql)
        }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case let s as String:
                s.withCString { sqlite3_bind_text(stmt, idx, $0, -1, SQLITE_TRANSIENT) }
            case let n as Int64:
                sqlite3_bind_int64(stmt, idx, n)
            case let n as Int:
                sqlite3_bind_int64(stmt, idx, Int64(n))
            case let d as Double:
                sqlite3_bind_double(stmt, idx, d)
            case let b as Bool:
                sqlite3_bind_int(stmt, idx, b ? 1 : 0)
            case nil:
                sqlite3_bind_null(stmt, idx)
            default:
                break
            }
        }
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW {
            throw FarmDbError.execFailed(sql)
        }
        return Int64(sqlite3_changes(handle))
    }

    /// 不抛错的写操作(失败静默, 与Java端try/catch忽略同语义)
    @discardableResult
    private func run(_ sql: String, params: [Any?] = []) -> Int64 {
        (try? exec(sql, params: params)) ?? 0
    }

    // MARK: - records (协议关键查询, 与 Db.java 同名方法同语义)

    /// 某uuid记录是否已存在(hash列) — 导入"先按uuid"的第一步
    public func hasRecordHash(_ hash: String) -> Bool {
        queryScalar("SELECT 1 FROM records WHERE hash=? LIMIT 1", params: [hash]) != nil
    }

    /// 本机mtime基准(无则0)
    public func recordMtime(_ hash: String) -> Int64 {
        queryScalar("SELECT IFNULL(mtime,0) FROM records WHERE hash=?", params: [hash]) as? Int64 ?? 0
    }

    /// 本机sVer基准(无则0)
    public func recordSver(_ hash: String) -> Int64 {
        queryScalar("SELECT IFNULL(sver,0) FROM records WHERE hash=?", params: [hash]) as? Int64 ?? 0
    }

    public func setRecordMtimeByHash(_ hash: String, _ mtime: Int64) {
        run("UPDATE records SET mtime=? WHERE hash=?", params: [mtime, hash])
    }

    public func setRecordSverByHash(_ hash: String, _ sver: Int64) {
        run("UPDATE records SET sver=? WHERE hash=?", params: [sver, hash])
    }

    /// 前缀回写: 补账号前缀后同步本地hash(此后各端同一身份)
    public func setHashById(_ id: Int64, _ hash: String) {
        run("UPDATE records SET hash=? WHERE id=?", params: [hash, id])
    }

    public func recordIdByUuid(_ hash: String) -> Int64 {
        queryScalar("SELECT id FROM records WHERE hash=?", params: [hash]) as? Int64 ?? 0
    }

    /// 墓碑传导: 删本地副本(连带items)
    public func deleteByUuid(_ hash: String) {
        let id = recordIdByUuid(hash)
        if id > 0 { deleteRecord(id) }
    }

    public func deleteRecord(_ id: Int64) {
        run("DELETE FROM items WHERE record_id=?", params: [id])
        run("DELETE FROM records WHERE id=?", params: [id])
    }

    /// 11字段导入去重(Db.hasContent): 10字段+保存时间ts
    public func hasContent(date: String, plot: String, op: String, crop: String,
                           pesticide: String, dose: String, note: String,
                           weather: String, method: String, weatherNote: String,
                           ts: String) -> Bool {
        queryScalar("SELECT 1 FROM records WHERE IFNULL(date,'')=? AND IFNULL(plot,'')=? " +
            "AND IFNULL(op,'')=? AND IFNULL(crop,'')=? AND IFNULL(pesticide,'')=? " +
            "AND IFNULL(dose,'')=? AND IFNULL(note,'')=? AND IFNULL(weather,'')=? " +
            "AND IFNULL(method,'')=? AND IFNULL(weather_note,'')=? AND IFNULL(ts,'')=? LIMIT 1",
            params: [date, plot, op, crop, pesticide, dose, note, weather, method, weatherNote, ts]) != nil
    }

    /// 新增记录(参数序对齐 Java addRecord), 返回id
    @discardableResult
    public func addRecord(date: String, plot: String, crop: String, op: String,
                          pesticide: String, dose: String, note: String,
                          photo: String? = nil, gps: String = "", hash: String,
                          ts: String, weather: String, method: String,
                          weatherNote: String) -> Int64 {
        run("INSERT INTO records(date,plot,crop,op,pesticide,dose,note,photo,gps,hash,ts," +
            "weather,method,weather_note) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            params: [date, plot, crop, op, pesticide, dose, note, photo, gps, hash, ts,
                     weather, method, weatherNote])
        return sqlite3_last_insert_rowid(handle)
    }

    /// 就地更新10个业务字段(不含mtime/sver/hash), 返回影响行数
    @discardableResult
    public func updateRecordByUuid(_ hash: String, date: String, plot: String, crop: String,
                                   op: String, pesticide: String, dose: String, note: String,
                                   weather: String, method: String, weatherNote: String) -> Int64 {
        run("UPDATE records SET date=?,plot=?,crop=?,op=?,pesticide=?,dose=?,note=?," +
            "weather=?,method=?,weather_note=? WHERE hash=?",
            params: [date, plot, crop, op, pesticide, dose, note, weather, method,
                     weatherNote, hash])
    }

    /// 修改申请裁决落地: 按uuid更新9个业务字段(不含plot, 对应Java updateByUuid)
    @discardableResult
    public func updateByUuid(_ hash: String, date: String, crop: String, op: String,
                             pesticide: String, dose: String, note: String,
                             method: String, weatherNote: String) -> Int64 {
        run("UPDATE records SET date=?,crop=?,op=?,pesticide=?,dose=?,note=?," +
            "method=?,weather_note=? WHERE hash=?",
            params: [date, crop, op, pesticide, dose, note, method, weatherNote, hash])
    }

    /// 裁决品项整表替换(照片保留本机文件)
    public func rewriteItemsByUuid(_ hash: String, _ items: [RecordItem]) {
        let id = recordIdByUuid(hash)
        if id > 0 { replaceItems(recordId: id, items) }
    }

    public func listItems(recordId: Int64) -> [RecordItem] {
        guard let stmt = prepare(
            "SELECT name,dose,note,photo,type,grp FROM items WHERE record_id=? ORDER BY id")
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, recordId)
        var out: [RecordItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(RecordItem(
                name: colText(stmt, 0), dose: colText(stmt, 1), note: colText(stmt, 2),
                type: colText(stmt, 4), grp: colText(stmt, 5), photoPath: colText(stmt, 3)))
        }
        return out
    }

    /// 整表替换品项(就地更新时连照片一起更新)
    public func replaceItems(recordId: Int64, _ items: [RecordItem]) {
        run("DELETE FROM items WHERE record_id=?", params: [recordId])
        addItems(recordId: recordId, items)
    }

    public func addItems(recordId: Int64, _ items: [RecordItem]) {
        for it in items {
            run("INSERT INTO items(record_id,name,dose,note,photo,type,grp) " +
                "VALUES(?,?,?,?,?,?,?)",
                params: [recordId, it.name, it.dose, it.note, it.photoPath, it.type, it.grp])
        }
    }

    /// 全量行(推送扫描用), 列序见 RecordRow
    public func listRecords() -> [RecordRow] {
        guard let stmt = prepare(
            "SELECT id,IFNULL(plot,''),IFNULL(date,''),IFNULL(crop,''),IFNULL(op,'')," +
            "IFNULL(pesticide,''),IFNULL(dose,''),IFNULL(note,''),IFNULL(ts,''),IFNULL(method,'')," +
            "IFNULL(weather_note,''),IFNULL(weather,''),IFNULL(hash,''),IFNULL(mtime,0),IFNULL(sver,0) " +
            "FROM records ORDER BY id") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [RecordRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(RecordRow(id: sqlite3_column_int64(stmt, 0),
                                 plot: colText(stmt, 1), date: colText(stmt, 2),
                                 crop: colText(stmt, 3), op: colText(stmt, 4),
                                 pesticide: colText(stmt, 5), dose: colText(stmt, 6),
                                 note: colText(stmt, 7), ts: colText(stmt, 8),
                                 method: colText(stmt, 9), weatherNote: colText(stmt, 10),
                                 weather: colText(stmt, 11), hash: colText(stmt, 12),
                                 mtime: sqlite3_column_int64(stmt, 13),
                                 sver: sqlite3_column_int64(stmt, 14)))
        }
        return out
    }

    // MARK: - ledger

    public func hasLedgerUuid(_ uuid: String) -> Bool {
        guard !uuid.isEmpty else { return false }
        return queryScalar("SELECT 1 FROM ledger WHERE uuid=? LIMIT 1", params: [uuid]) != nil
    }

    @discardableResult
    public func addLedger(date: String, kind: String, category: String, amount: Double,
                          plot: String, note: String, photo: String? = nil,
                          ts: String, uuid: String) -> Int64 {
        run("INSERT INTO ledger(date,kind,category,amount,plot,note,photo,ts,uuid) " +
            "VALUES(?,?,?,?,?,?,?,?,?)",
            params: [date, kind, category, amount, plot, note, photo, ts, uuid])
        return sqlite3_last_insert_rowid(handle)
    }

    public func setLedgerSver(_ uuid: String, _ sver: Int64) {
        run("UPDATE ledger SET sver=? WHERE uuid=?", params: [sver, uuid])
    }

    public func listLedger() -> [LedgerRow] {
        guard let stmt = prepare(
            "SELECT id,IFNULL(plot,''),IFNULL(date,''),IFNULL(kind,''),IFNULL(category,'')," +
            "amount,IFNULL(note,''),IFNULL(ts,''),IFNULL(photo,''),IFNULL(uuid,''),IFNULL(sver,0) " +
            "FROM ledger ORDER BY id") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [LedgerRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(LedgerRow(id: sqlite3_column_int64(stmt, 0),
                                 plot: colText(stmt, 1), date: colText(stmt, 2),
                                 kind: colText(stmt, 3), category: colText(stmt, 4),
                                 amount: sqlite3_column_double(stmt, 5),
                                 note: colText(stmt, 6), ts: colText(stmt, 7),
                                 photo: colText(stmt, 8), uuid: colText(stmt, 9),
                                 sver: sqlite3_column_int64(stmt, 10)))
        }
        return out
    }

    // MARK: - 墓碑(删除传播)

    /// 取走全部墓碑(推送成功后才删除, 失败由调用方重挂)
    public func takeTombstones() -> [(kind: String, uuid: String)] {
        guard let stmt = prepare("SELECT kind,uuid FROM sync_tombstones") else { return [] }
        var out: [(String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((colText(stmt, 0), colText(stmt, 1)))
        }
        sqlite3_finalize(stmt)
        run("DELETE FROM sync_tombstones")
        return out
    }

    public func addTombstone(kind: String, uuid: String) {
        run("INSERT OR REPLACE INTO sync_tombstones(kind,uuid,ts) VALUES(?,?,?)",
                  params: [kind, uuid, Int64(Date().timeIntervalSince1970 * 1000)])
    }

    // MARK: - 本地去重 (Sync.dedupeLocal 同SQL同语义)

    /// 内容去重: 10字段整条一致=同一条, 留小id删大id(连带items)
    @discardableResult
    public func dedupeRecords() -> Int {
        let rows = listRecords()
        var seen: [String: Int64] = [:]
        var kill: [Int64] = []
        for r in rows {
            let k = ContentKey.recordFingerprint(r.farmRecord)
            if let first = seen[k] {
                if r.id > first { kill.append(r.id) }
            } else {
                seen[k] = r.id
            }
        }
        for id in kill { deleteRecord(id) }
        return kill.count
    }

    /// 同uuid收敛: 双方有版本比版本, 否则比mtime, 新者胜(旧者连带items删)
    @discardableResult
    public func dedupeUuidSplit() -> Int {
        let rows = listRecords().filter { !$0.hash.isEmpty }
        var best: [String: RecordRow] = [:]
        var kill: [Int64] = []
        for r in rows {
            if let b = best[r.hash] {
                if MergeRules.challengerWins(incumbent: (sver: Int(b.sver), mtime: Int(b.mtime)),
                                             challenger: (sver: Int(r.sver), mtime: Int(r.mtime))) {
                    kill.append(b.id)
                    best[r.hash] = r
                } else {
                    kill.append(r.id)
                }
            } else {
                best[r.hash] = r
            }
        }
        for id in kill { deleteRecord(id) }
        return kill.count
    }

    /// 账本内容去重: date|kind|category|amount|plot|note 留首个
    @discardableResult
    public func dedupeLedger() -> Int {
        let rows = listLedger()
        var seen = Set<String>()
        var kill: [Int64] = []
        for r in rows {
            let k = ContentKey.ledgerFingerprint(LedgerEntry(
                date: r.date, kind: r.kind, category: r.category,
                amount: r.amount, plot: r.plot, note: r.note, uuid: r.uuid))
            if seen.contains(k) { kill.append(r.id) } else { seen.insert(k) }
        }
        for id in kill {
            run("DELETE FROM ledger WHERE id=?", params: [id])
        }
        return kill.count
    }

    // MARK: - plots / marks / dailynotes (池推送与组拉取用)

    public struct PlotRow: Equatable, Sendable {
        public let id: Int64
        public let name: String
        public let polygon: String
        public let area: Double
        public let thumb: String
        public let center: String
    }

    public func listPlots() -> [PlotRow] {
        guard let stmt = prepare(
            "SELECT id,IFNULL(name,''),IFNULL(polygon,''),IFNULL(area,0)," +
            "IFNULL(thumb,''),IFNULL(center,'') FROM plots ORDER BY id") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [PlotRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(PlotRow(id: sqlite3_column_int64(stmt, 0),
                               name: colText(stmt, 1), polygon: colText(stmt, 2),
                               area: sqlite3_column_double(stmt, 3),
                               thumb: colText(stmt, 4), center: colText(stmt, 5)))
        }
        return out
    }

    public func addPlot(name: String, polygon: String, area: Double,
                        thumb: String, center: String) {
        run("INSERT OR IGNORE INTO plots(name,polygon,area,thumb,center) " +
            "VALUES(?,?,?,?,?)", params: [name, polygon, area, thumb, center])
    }

    /// 回填授权地块的圈定图(仅当本地是授权壳时)
    public func updatePlotData(name: String, polygon: String, area: Double,
                               thumb: String, center: String) {
        run("UPDATE plots SET polygon=?,area=?,thumb=?,center=? WHERE name=?",
                  params: [polygon, area, thumb, center, name])
    }

    public struct MarkRow: Equatable, Hashable, Sendable {
        public let plot: String
        public let op: String
        public let date: String
        public let recordId: String  // 关联记录id(0=无)
    }

    public func listMarks() -> [MarkRow] {
        guard let stmt = prepare(
            "SELECT IFNULL(plot,''),IFNULL(op,''),IFNULL(date,'')," +
            "IFNULL(record_id,0) FROM marks ORDER BY id") else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [MarkRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(MarkRow(plot: colText(stmt, 0), op: colText(stmt, 1),
                               date: colText(stmt, 2),
                               recordId: String(sqlite3_column_int64(stmt, 3))))
        }
        return out
    }

    public struct DailyNoteRow: Equatable, Sendable {
        public let date: String
        public let content: String
        public let photos: String      // ;分隔多张
        public let ts: String
        public let weather: String
        public let gps: String
        public let star: Int
    }

    public func listDailyNotes() -> [DailyNoteRow] {
        guard let stmt = prepare(
            "SELECT IFNULL(date,''),IFNULL(content,''),IFNULL(photos,''),IFNULL(ts,'')," +
            "IFNULL(weather,''),IFNULL(gps,''),IFNULL(star,0) FROM dailynotes ORDER BY id")
        else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [DailyNoteRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(DailyNoteRow(date: colText(stmt, 0), content: colText(stmt, 1),
                                    photos: colText(stmt, 2), ts: colText(stmt, 3),
                                    weather: colText(stmt, 4), gps: colText(stmt, 5),
                                    star: Int(sqlite3_column_int(stmt, 6))))
        }
        return out
    }

    public func deletePlot(_ name: String) {
        run("DELETE FROM plots WHERE name=?", params: [name])
    }

    public func addDailyNote(date: String, content: String, photos: String,
                             ts: String, weather: String, gps: String, star: Bool) {
        run("INSERT INTO dailynotes(date,content,photos,ts,weather,gps,star) " +
            "VALUES(?,?,?,?,?,?,?)",
            params: [date, content, photos, ts, weather, gps, star ? 1 : 0])
    }

    /// 该地块最近一条非空crop记录("地块作物记忆"填充用)
    public func lastCropForPlot(_ plot: String) -> String {
        queryScalar("SELECT crop FROM records WHERE IFNULL(plot,'')=? " +
            "AND IFNULL(crop,'') != '' ORDER BY date DESC, id DESC LIMIT 1",
            params: [plot]) as? String ?? ""
    }

    /// 间隔提醒(首页间隔框)
    public func addMark(plot: String, op: String, date: String, recordId: Int64) {
        run("INSERT INTO marks(plot,op,date,ts,record_id) VALUES(?,?,?,?,?)",
                  params: [plot, op, date, Int64(Date().timeIntervalSince1970 * 1000), recordId])
    }

    /// 清该标记的旧墓碑: 同身份标记重建后能重新入池(不被旧墓碑压制)
    public func clearMarkTombstone(plot: String, op: String, date: String) {
        run("DELETE FROM sync_tombstones WHERE kind='mark' AND uuid=?",
                  params: [UuidCanon.markUuid(plot: plot, op: op, date: date)])
    }

    /// 清全部记录+账本(删组/撤回授权时)
    public func clearAllRecordsLedger() {
        run("DELETE FROM items")
        run("DELETE FROM records")
        run("DELETE FROM ledger")
    }

    // MARK: - 私有

    private func colText(_ stmt: OpaquePointer?, _ i: Int32) -> String {
        guard let p = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: p)
    }

    /// 取单行单列
    private func queryScalar(_ sql: String, params: [Any?]) -> Any? {
        guard let stmt = prepare(sql) else { return nil }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case let s as String:
                s.withCString { sqlite3_bind_text(stmt, idx, $0, -1, SQLITE_TRANSIENT) }
            case let n as Int64:
                sqlite3_bind_int64(stmt, idx, n)
            case let n as Int:
                sqlite3_bind_int64(stmt, idx, Int64(n))
            case let d as Double:
                sqlite3_bind_double(stmt, idx, d)
            case nil:
                sqlite3_bind_null(stmt, idx)
            default:
                break
            }
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        switch sqlite3_column_type(stmt, 0) {
        case SQLITE_INTEGER: return sqlite3_column_int64(stmt, 0)
        case SQLITE_FLOAT: return sqlite3_column_double(stmt, 0)
        case SQLITE_TEXT:
            if let p = sqlite3_column_text(stmt, 0) { return String(cString: p) }
            return nil
        default: return nil
        }
    }
}
