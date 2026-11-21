# 农小秘 iOS 版

农事记录 App「农小秘」的 Swift 移植，与 Android 版共用同一同步协议
(v37: uuid 身份证 + sVer 权威版本)，复用现有云端 `111.228.62.13:8910`。

## 结构
- `core/` — 协议核心（纯逻辑、无 UI 依赖），Termux(Linux) 可编译、可跑单元测试
- `app/` — SwiftUI App（仅 Xcode/CI 编译）

## 本地验证（Termux）
```
cd core && swift test    # 协议回归测试
```

## 打包未签名 IPA（免费、无需 Mac）
仓库推到 GitHub 公共仓库后，GitHub Actions（macOS 分钟对公共仓库免费）自动：
1. 跑核心协议测试
2. xcodebuild 打包未签名 `NongXiaoMiApp.app`
3. Actions 页产出 `NongXiaoMi.ipa` 工件

## 装到 iPhone（侧载，免费 Apple ID，7 天有效）
1. 手机浏览器打开 Actions 页，下载 `NongXiaoMi.ipa`（存到"文件"）
2. App Store 装 AltStore → My Apps → + → 选文件里的 IPA 安装
   （地区 App Store 没有 AltStore 时：电脑装 Sideloadly / 爱思助手，USB 连手机装）
3. 装完点信任（设置 → 通用 → VPN与设备管理）即可用；到期前 AltStore 内刷新

## 说明
- 服务器为 HTTP 明文（与 Android 版同一内网服务器），包配置已放开 ATS
  (NSAllowsArbitraryLoads)
- 照片暂不做跨设备同步（各端重压缩 base64 形态不同，协议指纹已排除照片）
- 后续上架 App Store / TestFlight 需 $99/年 Apple 开发者账号，打包流程不变
