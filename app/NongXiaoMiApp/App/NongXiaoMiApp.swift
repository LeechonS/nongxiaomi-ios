import SwiftUI

// MARK: - 农小秘 iOS 版入口
//
// 注意: 本target只有macOS/iOS可编译(SwiftUI), 协议逻辑在NongXiaoMiCore包里,
// Termux上已单独验证。

@main
struct NongXiaoMiApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .onAppear {
                    // 进前台恢复同步(对应Android端 MainActivity.onResume → pullImport)
                    appState.syncEngine?.tick()
                }
        }
    }
}

/// 根路由: 未登录→登录页, 已登录→主页
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isLoggedIn {
            MainView()
        } else {
            LoginView()
        }
    }
}
