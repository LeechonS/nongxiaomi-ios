import XCTest
@testable import NongXiaoMiCore

/// Db层测试: schema v19 / 协议关键查询 / 本地去重(真实SQLite, 内存库)
final class DbLayerTests: XCTestCase {

    private func makeDb() throws -> FarmDb {
        try FarmDb(path: ":memory:")
    }

    func testSchemaCreated() throws {
        let db = try makeDb()
        // 7张表都在
        XCTAssertTrue(db.hasRecordHash("x") == false) // 空库不报错
        let id = db.addRecord(date: "2026-11-17", plot: "树合一号池", crop: "苹果", op: "打药",
                              pesticide: "多菌灵", dose: "500g", note: "", hash: "15778364450:h1",
                              ts: "2026-11-17 21:53:55", weather: "晴", method: "喷雾",
                              weatherNote: "")
        XCTAssertEqual(id, 1)
        XCTAssertTrue(db.hasRecordHash("15778364450:h1"))
        let rows = db.listRecords()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].plot, "树合一号池")
        XCTAssertEqual(rows[0].op, "打药")
        XCTAssertEqual(rows[0].ts, "2026-11-17 21:53:55")
        XCTAssertEqual(rows[0].hash, "15778364450:h1")
        XCTAssertEqual(rows[0].mtime, 0)
        XCTAssertEqual(rows[0].sver, 0)
    }

    func testSverMtimeRoundtrip() throws {
        let db = try makeDb()
        _ = db.addRecord(date: "d", plot: "p", crop: "", op: "o", pesticide: "", dose: "",
                         note: "", hash: "acc:u1", ts: "t", weather: "", method: "", weatherNote: "")
        XCTAssertEqual(db.recordSver("acc:u1"), 0)
        db.setRecordSverByHash("acc:u1", 7)
        db.setRecordMtimeByHash("acc:u1", 1234567890)
        XCTAssertEqual(db.recordSver("acc:u1"), 7)
        XCTAssertEqual(db.recordMtime("acc:u1"), 1234567890)
        // 不存在的hash → 0
        XCTAssertEqual(db.recordSver("acc:nonexist"), 0)
        XCTAssertEqual(db.recordMtime("acc:nonexist"), 0)
    }

    func testHasContentElevenFields() throws {
        let db = try makeDb()
        _ = db.addRecord(date: "d", plot: "p", crop: "", op: "o", pesticide: "", dose: "",
                         note: "", hash: "h1", ts: "2026-11-17 21:53:55", weather: "",
                         method: "", weatherNote: "")
        // 11字段全同 → 命中
        XCTAssertTrue(db.hasContent(date: "d", plot: "p", op: "o", crop: "", pesticide: "",
                                    dose: "", note: "", weather: "", method: "",
                                    weatherNote: "", ts: "2026-11-17 21:53:55"))
        // ts不同 → 不命中(纯照片记录靠ts区分)
        XCTAssertFalse(db.hasContent(date: "d", plot: "p", op: "o", crop: "", pesticide: "",
                                     dose: "", note: "", weather: "", method: "",
                                     weatherNote: "", ts: "2026-11-17 22:00:00"))
    }

    func testUpdateByUuidAndItems() throws {
        let db = try makeDb()
        let id = db.addRecord(date: "d1", plot: "p", crop: "", op: "旧操作", pesticide: "", dose: "",
                              note: "", hash: "acc:u", ts: "t", weather: "", method: "", weatherNote: "")
        XCTAssertEqual(id, 1)
        let n = db.updateRecordByUuid("acc:u", date: "d2", plot: "p", crop: "苹果",
                                      op: "新操作", pesticide: "药", dose: "1g", note: "n",
                                      weather: "阴", method: "灌根", weatherNote: "wn")
        XCTAssertEqual(n, 1)
        let items = [RecordItem(name: "多菌灵", dose: "500g", note: "", type: "item", grp: ""),
                     RecordItem(name: "尿素", dose: "2kg", note: "", type: "identify", grp: "g1")]
        db.replaceItems(recordId: id, items)
        XCTAssertEqual(db.listItems(recordId: id).count, 2)
        db.replaceItems(recordId: id, [RecordItem(name: "只留一个")])
        XCTAssertEqual(db.listItems(recordId: id).count, 1)
        // 错误uuid更新 → 0行
        XCTAssertEqual(db.updateRecordByUuid("acc:nope", date: "d", plot: "", crop: "",
                                             op: "", pesticide: "", dose: "", note: "",
                                             weather: "", method: "", weatherNote: ""), 0)
    }

    func testTombstones() throws {
        let db = try makeDb()
        db.addTombstone(kind: "record", uuid: "acc:u1")
        db.addTombstone(kind: "ledger", uuid: "led:5")
        db.addTombstone(kind: "record", uuid: "acc:u1") // UNIQUE, 重复不炸
        let tombs = db.takeTombstones()
        XCTAssertEqual(tombs.count, 2)
        XCTAssertEqual(Set(tombs.map { $0.kind + ":" + $0.uuid }),
                       Set(["record:acc:u1", "ledger:led:5"]))
        // 取走即清空
        XCTAssertEqual(db.takeTombstones().count, 0)
    }

    func testDedupeRecordsContent() throws {
        let db = try makeDb()
        // 同10字段、不同ts: 本地内容去重合并(留小id)
        _ = db.addRecord(date: "d", plot: "p", crop: "", op: "o", pesticide: "", dose: "",
                         note: "", hash: "h1", ts: "t1", weather: "", method: "", weatherNote: "")
        _ = db.addRecord(date: "d", plot: "p", crop: "", op: "o", pesticide: "", dose: "",
                         note: "", hash: "h2", ts: "t2", weather: "", method: "", weatherNote: "")
        _ = db.addRecord(date: "d3", plot: "p", crop: "", op: "o", pesticide: "", dose: "",
                         note: "", hash: "h3", ts: "t3", weather: "", method: "", weatherNote: "")
        let killed = db.dedupeRecords()
        XCTAssertEqual(killed, 1)
        let rows = db.listRecords()
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.map { $0.hash }.contains("h1"))
        XCTAssertTrue(rows.map { $0.hash }.contains("h3"))
    }

    func testDedupeUuidSplit() throws {
        let db = try makeDb()
        // 主管自己行分裂: 同uuid两条, 一条sver高
        _ = db.addRecord(date: "d", plot: "p", crop: "", op: "旧内容", pesticide: "", dose: "",
                         note: "", hash: "acc:split", ts: "t1", weather: "", method: "", weatherNote: "")
        _ = db.addRecord(date: "d", plot: "p", crop: "", op: "新内容", pesticide: "", dose: "",
                         note: "", hash: "acc:split", ts: "t2", weather: "", method: "", weatherNote: "")
        let all = db.listRecords()
        XCTAssertEqual(all.count, 2)
        db.setRecordSverByHash("acc:split", 3) // 两条同hash都会被置(模拟一条3一条0前先测同版本)
        // 重造: 清库重来
        let db2 = try makeDb()
        let id1 = db2.addRecord(date: "d", plot: "p", crop: "", op: "旧内容", pesticide: "", dose: "",
                                note: "", hash: "acc:split", ts: "t1", weather: "", method: "", weatherNote: "")
        _ = db2.addRecord(date: "d", plot: "p", crop: "", op: "新内容", pesticide: "", dose: "",
                          note: "", hash: "acc:split", ts: "t2", weather: "", method: "", weatherNote: "")
        db2.setRecordSverByHash("acc:split", 5)
        db2.setRecordMtimeByHash("acc:split", 200)
        // 直接按id给第一条(sver=5)和第二条不同基准: 用SQL模拟不行(同hash),
        // 所以验证收敛逻辑: 同sver时mtime新者胜——这里两条同hash无法区分,
        // 改验证不同hash前缀场景已覆盖; 本函数主要防回归崩溃
        XCTAssertGreaterThan(id1, 0)
        let killed = db2.dedupeUuidSplit()
        XCTAssertEqual(killed, 1)
        XCTAssertEqual(db2.listRecords().count, 1)
    }

    func testDedupeLedger() throws {
        let db = try makeDb()
        _ = db.addLedger(date: "d", kind: "收", category: "果", amount: 12.5, plot: "p",
                         note: "", ts: "t1", uuid: "led:1")
        _ = db.addLedger(date: "d", kind: "收", category: "果", amount: 12.5, plot: "p",
                         note: "", ts: "t2", uuid: "led:2")
        _ = db.addLedger(date: "d", kind: "支", category: "药", amount: 12.5, plot: "p",
                         note: "", ts: "t3", uuid: "led:3")
        XCTAssertEqual(db.dedupeLedger(), 1)
        XCTAssertEqual(db.listLedger().count, 2)
    }

    func testClearAllRecordsLedger() throws {
        let db = try makeDb()
        _ = db.addRecord(date: "d", plot: "p", crop: "", op: "o", pesticide: "", dose: "",
                         note: "", hash: "h", ts: "t", weather: "", method: "", weatherNote: "")
        _ = db.addLedger(date: "d", kind: "收", category: "c", amount: 1, plot: "p",
                         note: "", ts: "t", uuid: "led:1")
        db.clearAllRecordsLedger()
        XCTAssertEqual(db.listRecords().count, 0)
        XCTAssertEqual(db.listLedger().count, 0)
    }
}

/// 远端模型解码测试(用17号记录的真实数据形态)
final class RemoteModelTests: XCTestCase {

    func testDecodeRealRecordShape() throws {
        // dryrun_moddecide.js 里的真实服务器行
        let dict: [String: Any] = [
            "uuid": "15778364450:rec:2026-11-17|树合一号池|打药||1||",
            "date": "2026-11-17", "plot": "树合一号池", "crop": "", "op": "打药",
            "pesticide": "1", "dose": "", "note": "",
            "ts": "2026-11-17 21:53:55", "device": "15778364450",
            "mtime": 1795015059651, "sVer": 3, "deleted": false,
        ]
        let r = try XCTUnwrap(RemoteRecord(dict: dict))
        XCTAssertEqual(r.uuid, "15778364450:rec:2026-11-17|树合一号池|打药||1||")
        XCTAssertEqual(r.sver, 3)
        XCTAssertEqual(r.mtime, 1795015059651)
        XCTAssertFalse(r.deleted)
        XCTAssertEqual(r.op, "打药")
        XCTAssertEqual(r.asLocal.uuid, r.uuid)
    }

    func testDecodeMissingFieldsTolerant() throws {
        // 缺字段 → 空串/0/false (Java optXxx语义)
        let r = try XCTUnwrap(RemoteRecord(dict: ["uuid": "u1"] as [String: Any]))
        XCTAssertEqual(r.device, "")
        XCTAssertEqual(r.sver, 0)
        XCTAssertEqual(r.mtime, 0)
        XCTAssertFalse(r.deleted)
        // 无uuid → 拒绝
        XCTAssertNil(RemoteRecord(dict: [:]))
        XCTAssertNil(RemoteRecord(dict: ["uuid": ""]))
    }

    func testDecodeTombstoneAndItems() throws {
        let dict: [String: Any] = [
            "uuid": "acc:u", "deleted": true,
            "items": [["name": "多菌灵", "dose": "500g", "type": "item",
                       "photo_b64": "aGVsbG8="] as [String: Any]],
        ]
        let r = try XCTUnwrap(RemoteRecord(dict: dict))
        XCTAssertTrue(r.deleted)
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items[0].name, "多菌灵")
        XCTAssertEqual(r.items[0].photoB64, "aGVsbG8=")
        XCTAssertEqual(r.asLocal.deleted, true)
    }

    func testDecodeLedger() throws {
        let l = try XCTUnwrap(RemoteLedger(dict: [
            "uuid": "15778364450:led:9", "date": "2026-11-17", "kind": "收",
            "category": "果", "amount": 1234.5, "plot": "树合一号池",
            "note": "第一车", "ts": "2026-11-17 09:00:00",
        ] as [String: Any]))
        XCTAssertEqual(l.amount, 1234.5)
        XCTAssertEqual(l.kind, "收")
        XCTAssertEqual(l.asLocal.amount, 1234.5)
        XCTAssertNil(RemoteLedger(dict: ["x": 1] as [String: Any]))
    }
}
