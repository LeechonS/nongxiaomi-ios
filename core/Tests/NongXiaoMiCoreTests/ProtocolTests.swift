import XCTest
@testable import NongXiaoMiCore

/// 协议回归测试: 覆盖 Android 端 v36→v37 修复史里踩过的真实场景
final class ProtocolTests: XCTestCase {

    // MARK: - Java String.hashCode (参考值由Python独立计算, 验证32位溢出与UTF-16口径)

    func testJavaStringHashReference() {
        XCTAssertEqual(PoolSig.javaStringHash("abc"), 96354)
        XCTAssertEqual(PoolSig.javaStringHash("hello"), 99162322)
        XCTAssertEqual(PoolSig.javaStringHash("hellow"), -1220935195) // 溢出为负
        XCTAssertEqual(PoolSig.javaStringHash(String(repeating: "x", count: 100)), 1680682496)
        XCTAssertEqual(PoolSig.javaStringHash("中文测试|树合一号池"), -1954018246)
        XCTAssertEqual(PoolSig.javaStringHash("uuid=15778364450:abc123;stype=record;"), -479879879)
    }

    // MARK: - Java Double.toString 形态

    func testJavaDoubleString() {
        XCTAssertEqual(JavaNumber.doubleString(0.0), "0.0")
        XCTAssertEqual(JavaNumber.doubleString(-0.0), "-0.0")
        XCTAssertEqual(JavaNumber.doubleString(12.0), "12.0")
        XCTAssertEqual(JavaNumber.doubleString(12.5), "12.5")
        XCTAssertEqual(JavaNumber.doubleString(0.5), "0.5")
        XCTAssertEqual(JavaNumber.doubleString(100.0), "100.0")
        XCTAssertEqual(JavaNumber.doubleString(-12.5), "-12.5")
        // 边界: 1e-3 与 1e7 两侧
        XCTAssertEqual(JavaNumber.doubleString(0.001), "0.001")
        XCTAssertEqual(JavaNumber.doubleString(0.0001), "1.0E-4")
        XCTAssertEqual(JavaNumber.doubleString(9999999.0), "9999999.0")
        XCTAssertEqual(JavaNumber.doubleString(1e7), "1.0E7")
        XCTAssertEqual(JavaNumber.doubleString(1e10), "1.0E10")
        XCTAssertEqual(JavaNumber.doubleString(1e-5), "1.0E-5")
        XCTAssertEqual(JavaNumber.doubleString(1e16), "1.0E16")
    }

    // MARK: - 池签名 sig (Backup.sigOf)

    func testSigKeyOrderInvariant() {
        let a = PoolSig.sig(["uuid": "15778364450:abc123", "date": "2026-11-17",
                             "stype": "record", "mtime": "123"], keepPhotoB64s: false)
        let b = PoolSig.sig(["mtime": "123", "date": "2026-11-17",
                             "uuid": "15778364450:abc123", "stype": "record"], keepPhotoB64s: false)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, "441664485") // Python参考值
    }

    func testSigExcludesVolatileKeys() {
        // device/mtime/stype/photo_b64 排除: 变化不影响签名
        let base = PoolSig.sig(["uuid": "15778364450:abc123", "date": "2026-11-17"], keepPhotoB64s: false)
        let volatile = PoolSig.sig(["uuid": "15778364450:abc123", "date": "2026-11-17",
                                    "device": "phone-A", "mtime": "999999",
                                    "stype": "record", "photo_b64": "aGVsbG8="], keepPhotoB64s: false)
        XCTAssertEqual(base, volatile)
        // 但内容字段变化必须变签名(编辑检测)
        let edited = PoolSig.sig(["uuid": "15778364450:abc123", "date": "2026-11-18"], keepPhotoB64s: false)
        XCTAssertNotEqual(base, edited)
    }

    func testSigNotePhotoBehavior() {
        // 日常观察(keepPhotoB64s=true): 含照片 → 加/换照片算编辑
        let withPhoto = PoolSig.sig(["uuid": "dn:2026-11-17 21:53:55", "date": "2026-11-17",
                                     "content": "晴,30度", "photo_b64s": "[\"aGVsbG8=\"]",
                                     "mtime": "1", "stype": "note"], keepPhotoB64s: true)
        XCTAssertEqual(withPhoto, "-1551279119") // Python参考值(按Java sigOf逐条含尾分号重算)
        // keepPhotoB64s=false: 照片被排除
        let without = PoolSig.sig(["uuid": "dn:2026-11-17 21:53:55", "date": "2026-11-17",
                                   "content": "晴,30度", "photo_b64s": "[\"aGVsbG8=\"]",
                                   "mtime": "1", "stype": "note"], keepPhotoB64s: false)
        XCTAssertNotEqual(withPhoto, without)
    }

    // MARK: - uuid身份规则

    func testRelayUuidLegacyFingerprint() {
        // 真实数据(17号记录): hash空的远古记录按内容现算 rec:fp
        let u = UuidCanon.relayUuid(hash: "", account: "15778364450",
                                    date: "2026-11-17", plot: "树合一号池", op: "打药", crop: "",
                                    pesticide: "1", dose: "", note: "",
                                    ts: "2026-11-17 21:53:55")
        XCTAssertEqual(u, "15778364450:rec:2026-11-17|树合一号池|打药||1|||2026-11-17 21:53:55")
    }

    func testRelayUuidPrefixRules() {
        // 无前缀自有记录 → 补账号前缀
        XCTAssertEqual(UuidCanon.relayUuid(hash: "abc123", account: "15778364450",
                                           date: "", plot: "", op: "", crop: "",
                                           pesticide: "", dose: "", note: "", ts: ""),
                       "15778364450:abc123")
        // 已带自己前缀 → 原样(不再叠)
        XCTAssertEqual(UuidCanon.relayUuid(hash: "15778364450:abc123", account: "15778364450",
                                           date: "", plot: "", op: "", crop: "",
                                           pesticide: "", dose: "", note: "", ts: ""),
                       "15778364450:abc123")
        // 已带他人前缀(授权导入的对方副本) → 原样推, 杜绝双前缀幽灵
        XCTAssertEqual(UuidCanon.relayUuid(hash: "13800000000:copy", account: "15778364450",
                                           date: "", plot: "", op: "", crop: "",
                                           pesticide: "", dose: "", note: "", ts: ""),
                       "13800000000:copy")
        // 非11位账号 → 不补
        XCTAssertEqual(UuidCanon.relayUuid(hash: "abc123", account: "12345",
                                           date: "", plot: "", op: "", crop: "",
                                           pesticide: "", dose: "", note: "", ts: ""),
                       "abc123")
    }

    func testCanonDoublePrefix() {
        // 双前缀 → 内层
        XCTAssertEqual(UuidCanon.canon("13800000000:rec:15778364450:abc123"),
                       "15778364450:abc123")
        // 遗留指纹号(7段/8段) → 原样
        XCTAssertEqual(UuidCanon.canon("15778364450:rec:2026-11-17|树合一号池|打药||1||"),
                       "15778364450:rec:2026-11-17|树合一号池|打药||1||")
        XCTAssertEqual(UuidCanon.canon("15778364450:rec:2026-11-17|树合一号池|打药||1|||2026-11-17 21:53:55"),
                       "15778364450:rec:2026-11-17|树合一号池|打药||1|||2026-11-17 21:53:55")
        // 正常号 → 原样
        XCTAssertEqual(UuidCanon.canon("15778364450:abc123"), "15778364450:abc123")
        XCTAssertEqual(UuidCanon.canon(""), "")
    }

    func testPoolUuidRules() {
        XCTAssertEqual(UuidCanon.poolUuid("abc123", phone: "15778364450"), "15778364450:abc123")
        // b: 遗留行不动
        XCTAssertEqual(UuidCanon.poolUuid("b:2026-11-17 21:53:55:树合一号池", phone: "15778364450"),
                       "b:2026-11-17 21:53:55:树合一号池")
        // 已带前缀不动
        XCTAssertEqual(UuidCanon.poolUuid("13800000000:abc", phone: "15778364450"), "13800000000:abc")
        XCTAssertEqual(UuidCanon.poolUuid("abc123", phone: "12345"), "abc123")
    }

    // MARK: - 导入合并裁决 (importRemote)

    private func rec(sver: Int, mtime: Int, deleted: Bool = false) -> FarmRecord {
        FarmRecord(uuid: "15778364450:abc123", mtime: mtime, sver: sver, deleted: deleted)
    }

    func testImportStrictOldVersionRejected() {
        // v37核心: 重登恢复的旧快照(sVer小)哪怕时间戳超前2100小时也不采信
        let local = rec(sver: 5, mtime: 100)
        let stale = rec(sver: 3, mtime: 100 + 2100 * 3600 * 1000)
        XCTAssertEqual(MergeRules.importRecord(local: local, incoming: stale), .skip)
    }

    func testImportNewerVersionWinsRegardlessOfMtime() {
        let local = rec(sver: 5, mtime: 999_999_999)
        let newer = rec(sver: 6, mtime: 100)
        XCTAssertEqual(MergeRules.importRecord(local: local, incoming: newer), .update)
    }

    func testImportSameVersionFallsBackToMtime() {
        // 同版本+mtime新: 主管编辑场景(中继旧副本+主管池新副本同版本)
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 5, mtime: 200),
                                               incoming: rec(sver: 5, mtime: 300)), .update)
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 5, mtime: 300),
                                               incoming: rec(sver: 5, mtime: 200)), .skip)
        // 同版本同mtime: 留本地
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 5, mtime: 300),
                                               incoming: rec(sver: 5, mtime: 300)), .skip)
    }

    func testImportMissingVersionFallsBackToMtime() {
        // 任一方无版本 → mtime新者胜
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 0, mtime: 200),
                                               incoming: rec(sver: 7, mtime: 100)), .skip)
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 5, mtime: 200),
                                               incoming: rec(sver: 0, mtime: 300)), .update)
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 0, mtime: 200),
                                               incoming: rec(sver: 0, mtime: 300)), .update)
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 0, mtime: 300),
                                               incoming: rec(sver: 0, mtime: 300)), .skip)
    }

    func testImportMtimeZeroAccepted() {
        // 双方都无mtime基准 → 接受(无法比较时不拦)
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 0, mtime: 0),
                                               incoming: rec(sver: 0, mtime: 0)), .update)
    }

    func testImportTombstoneAndInsert() {
        XCTAssertEqual(MergeRules.importRecord(local: rec(sver: 5, mtime: 100),
                                               incoming: rec(sver: 9, mtime: 200, deleted: true)),
                       .tombstone)
        XCTAssertEqual(MergeRules.importRecord(local: nil, incoming: rec(sver: 1, mtime: 1)),
                       .insert)
    }

    func testImportLedger() {
        let led = LedgerEntry(uuid: "led:42")
        XCTAssertEqual(MergeRules.importLedger(localHasUuid: false, incoming: led), .insert)
        XCTAssertEqual(MergeRules.importLedger(localHasUuid: true, incoming: led), .skip)
        XCTAssertEqual(MergeRules.importLedger(localHasUuid: true,
                                               incoming: LedgerEntry(uuid: "led:42", deleted: true)),
                       .tombstone)
    }

    // MARK: - 本地同uuid收敛 (dedupeLocal)

    func testChallengerWins() {
        // 双方有版本: 版本严格大才赢
        XCTAssertFalse(MergeRules.challengerWins(incumbent: (sver: 5, mtime: 100),
                                                 challenger: (sver: 4, mtime: 9999)))
        XCTAssertTrue(MergeRules.challengerWins(incumbent: (sver: 5, mtime: 100),
                                                challenger: (sver: 6, mtime: 1)))
        XCTAssertFalse(MergeRules.challengerWins(incumbent: (sver: 5, mtime: 100),
                                                 challenger: (sver: 5, mtime: 9999)))
        // 一方无版本: 落回mtime
        XCTAssertFalse(MergeRules.challengerWins(incumbent: (sver: 0, mtime: 200),
                                                 challenger: (sver: 7, mtime: 100)))
        XCTAssertTrue(MergeRules.challengerWins(incumbent: (sver: 0, mtime: 200),
                                                challenger: (sver: 0, mtime: 300)))
    }

    // MARK: - 内容指纹去重

    func testContentDedupeKeepsFirst() {
        // 同10字段指纹、不同ts → 本地去重仍合并(与hasContent的11字段口径不同)
        let a = FarmRecord(date: "2026-11-17", plot: "树合一号池", op: "打药", ts: "2026-11-17 21:53:55")
        let b = FarmRecord(date: "2026-11-17", plot: "树合一号池", op: "打药", ts: "2026-11-17 22:00:00")
        let c = FarmRecord(date: "2026-11-18", plot: "树合一号池", op: "打药", ts: "2026-11-18 08:00:00")
        XCTAssertEqual(ContentKey.recordFingerprint(a), ContentKey.recordFingerprint(b))
        XCTAssertNotEqual(ContentKey.recordFingerprint(a), ContentKey.recordFingerprint(c))
        // 但导入去重键含ts → 不同ts视为不同条目
        XCTAssertNotEqual(ContentKey.recordContentKey(a), ContentKey.recordContentKey(b))
        let kill = MergeRules.contentDedupeKeepFirst([a, b, c], key: { ContentKey.recordFingerprint($0) })
        XCTAssertEqual(kill, [1])
    }

    func testLedgerFingerprint() {
        let l1 = LedgerEntry(date: "2026-11-17", kind: "收", category: "种子", amount: 12.5)
        let l2 = LedgerEntry(date: "2026-11-17", kind: "收", category: "种子", amount: 12.0)
        XCTAssertTrue(ContentKey.ledgerFingerprint(l1).contains("|12.5|"))
        XCTAssertTrue(ContentKey.ledgerFingerprint(l2).contains("|12.0|"))
        XCTAssertEqual(JavaNumber.doubleString(12.5), "12.5")
        XCTAssertEqual(JavaNumber.doubleString(12.0), "12.0")
    }
}
