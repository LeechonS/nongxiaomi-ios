// swift-tools-version:5.9
// 农小秘 iOS 版 — App包(SwiftUI, 仅Xcode/CI可编译; 协议逻辑在../core, Termux已验证)
import PackageDescription

let package = Package(
    name: "NongXiaoMiApp",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(path: "../core"),
    ],
    targets: [
        .executableTarget(
            name: "NongXiaoMiApp",
            dependencies: [
                // 路径依赖的包身份=目录名"core"(不是manifest名)
                .product(name: "NongXiaoMiCore", package: "core"),
            ],
            path: "NongXiaoMiApp"
        ),
    ]
)
