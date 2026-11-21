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
                .product(name: "NongXiaoMiCore", package: "NongXiaoMiCore"),
            ],
            path: "NongXiaoMiApp"
        ),
    ]
)
