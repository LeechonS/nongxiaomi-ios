// swift-tools-version:5.9
// 农小秘 iOS 版 — 核心协议包
// 纯逻辑层: uuid身份规则/内容指纹/合并裁决/池签名, 与Android端(v37协议)逐条对齐。
// 本包不依赖UIKit/SwiftUI, 可在Linux(Termux)上编译+跑单元测试,
// 只有最后一步"打包签名上传"需要Mac上的Xcode。
import PackageDescription

let package = Package(
    name: "NongXiaoMiCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "NongXiaoMiCore", targets: ["NongXiaoMiCore"]),
    ],
    targets: [
        // 系统sqlite3模块: Termux的Swift不带SQLite3 modulemap, Apple平台同样适用
        .systemLibrary(name: "SQLite3C"),
        .target(name: "NongXiaoMiCore", dependencies: ["SQLite3C"]),
        .testTarget(name: "NongXiaoMiCoreTests", dependencies: ["NongXiaoMiCore"]),
    ]
)
