# 农小秘 iOS 版

## 结构

```
farm_ios/
  core/          # SwiftPM包 NongXiaoMiCore — 纯协议逻辑(可在Termux/Linux编译+测试)
  app/           # SwiftUI应用源码 — 最终打包需Mac + Xcode
```

## 为什么分两层

- `core` 不依赖 UIKit/SwiftUI，全部是纯计算逻辑（uuid身份规则、内容指纹、
  sVer版本门合并裁决、墓碑传导、池签名）。Linux 版 Swift（Termux 已装）
  就能编译和跑单元测试，**协议正确性在拿到 Mac 之前就能验证**。
- `app` 是 SwiftUI 界面层（对应 Android 端 17 个页面）。SwiftUI 只在
  Apple 平台可编译，需要 Mac 上的 Xcode 才能验证和打包。

## 与 Android 端对应关系（协议移植来源）

| iOS 文件 | Android 来源 | 规则 |
|---|---|---|
| `UuidCanon.swift` | `Sync.pushPending:550-561` / `Backup.pushPoolLocked:445-448` / 服务端canonUuid | uuid前缀补全、双前缀正规化、各类池条目身份 |
| `ContentKey.swift` | `Sync.contentFp:261-270` / `Db.hasContent:648` / `dedupeLocal:362-370` | 10字段本地指纹 / 11字段导入键(含ts) / 账本键 |
| `MergeRules.swift` | `Sync.importRemote:742-832` / `dedupeLocal:314-379` | sVer严格旧跳过→版本相同/无版本落回mtime新者胜；墓碑传导；本地收敛 |
| `PoolSig.swift` | `Backup.sigOf:375-391` | 键字典序拼串取Java String.hashCode；排除device/mtime/stype/照片b64 |
| `JavaNumber.doubleString` | Java `Double.toString` | 1e-3\~1e7小数(补.0)，否则d.E±ee |

## 已踩过的坑（移植必须遵守，来自 Android v36→v37 修复史）

1. **双前缀幽灵**：已带任意 11 位前缀的 uuid 原样推，绝不叠前缀
2. **旧快照时间戳攻击**：sVer 严格旧直接跳过，mtime 再新也不采信
3. **同版本内容变**：版本相同落回 mtime 新者胜（主管编辑场景）
4. **contentKey 必须排除 photo_b64**：各端重压照片 base64 必不同，
   含进去会让 sVer/dataVer 空转、全量拉推打满线路
5. **b: 遗留行不补前缀**（池内本地身份）
6. **账本副本不回推**（hash 非空的 led 行跳过）

## 构建

```bash
# Termux (协议层验证)
cd farm_ios/core && swift test

# Mac (完整应用)
# Xcode 打开 app/ 下的 .xcodeproj, 签名后运行/导出
```
