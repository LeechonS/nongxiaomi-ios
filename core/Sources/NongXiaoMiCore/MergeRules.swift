import Foundation

// MARK: - 合并裁决(v37双腿协议: uuid=身份证, sVer=服务端权威版本)

/// 组数据导入裁决
public enum ImportDecision: Equatable, Sendable {
    /// 本机已有此uuid且入端更旧(版本严格旧, 或落回mtime不新) → 跳过
    case skip
    /// 本机已有此uuid且入端更新 → 就地更新(字段+items+mtime+sver)
    case update
    /// 本机没有此uuid → 插入(插入前仍过11字段内容去重, 命中则改skip)
    case insert
    /// 墓碑行 → 删本地副本(删除传导, 也用于清洗历史分裂行)
    case tombstone
}

public enum MergeRules {

    /// 组数据导入裁决 (Sync.importRemote:742-832)
    /// - Parameter local: 本机同uuid行(nil=本机没有)
    public static func importRecord(local: FarmRecord?, incoming: FarmRecord) -> ImportDecision {
        if incoming.deleted { return .tombstone }
        guard let l = local else { return .insert }
        // [sVer] 严格旧版本直接跳过(重登恢复的旧快照盖不掉新内容)
        if l.sver > 0 && incoming.sver > 0 && incoming.sver < l.sver { return .skip }
        // 版本相同或任一方无版本: 落回mtime新者胜——同一uuid可能在中继+主管池
        // 出现两遍, 版本相同时靠mtime认出主管的新改动
        if l.sver <= 0 || incoming.sver <= 0 || incoming.sver == l.sver {
            if l.mtime > 0 && incoming.mtime > 0 && incoming.mtime <= l.mtime { return .skip }
        }
        return .update
    }

    /// 账本导入裁决 (importRemote:818-829): 仅"uuid未入本地账本"才插入, 不比版本
    public static func importLedger(localHasUuid: Bool, incoming: LedgerEntry) -> ImportDecision {
        if incoming.deleted { return .tombstone }
        return localHasUuid ? .skip : .insert
    }

    /// 本地同uuid收敛胜者 (Sync.dedupeLocal:339-356):
    /// 双方都有版本→版本高者胜; 否则mtime新者胜; 平局留小id(incoming不赢)
    /// - Returns: 挑战者(后一行)是否胜出现任(前一行)
    public static func challengerWins(incumbent: (sver: Int, mtime: Int),
                                      challenger: (sver: Int, mtime: Int)) -> Bool {
        (challenger.sver > 0 && incumbent.sver > 0)
            ? challenger.sver > incumbent.sver
            : challenger.mtime > incumbent.mtime
    }

    /// 内容去重(整条打包, 全字段一致才是同一条):
    /// 按id升序遍历, 首个保留, 后续同键行删除(记录连带items, dedupeLocal:314-338/362-377)
    /// - Returns: 应删除的下标集合
    public static func contentDedupeKeepFirst<T>(_ rows: [T], key: (T) -> String) -> Set<Int> {
        var seen: [String: Int] = [:]
        var kill: Set<Int> = []
        for (i, row) in rows.enumerated() {
            let k = key(row)
            if seen[k] != nil {
                kill.insert(i)
            } else {
                seen[k] = i
            }
        }
        return kill
    }
}
