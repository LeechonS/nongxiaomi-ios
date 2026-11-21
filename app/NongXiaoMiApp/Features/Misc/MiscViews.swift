import SwiftUI
import NongXiaoMiCore

// MARK: - 同步状态页(对应 SyncActivity.java: 手动同步/角色/版本/错误日志)
// MARK: - 我的页(对应 MineActivity.java: 账号/登出/关于)
// MARK: - 统计页(对应 StatsActivity.java: 记录/账本概览)

struct SyncView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") {
                    LabeledRow("账号", appState.phone.isEmpty ? "未登录" : appState.phone)
                    LabeledRow("服务器", appState.server)
                    LabeledRow("上次同步",
                               appState.lastSyncAt.map { ISO8601TimeFormat.short($0) } ?? "—")
                    if !appState.syncMessage.isEmpty {
                        LabeledRow("提示", appState.syncMessage)
                    }
                }
                Section("我的角色") {
                    if appState.roles.isEmpty {
                        Text("无(个人使用)")
                    } else {
                        // roles是元组数组, 键路径不能指元组元素 → 按下标遍历
                        ForEach(appState.roles.indices, id: \.self) { i in
                            Text("\(appState.roles[i].role == "B" ? "主管" : "分管") · 组 \(appState.roles[i].code)")
                        }
                    }
                }
                Section {
                    Button("立即同步") {
                        appState.syncEngine?.tick()
                    }
                    Button("重新拉取角色") {
                        Task { await appState.refreshRoles() }
                    }
                }
            }
            .navigationTitle("同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// 我的
struct MineView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledRow("手机号", appState.phone)
                    LabeledRow("设备ID", String(appState.installUid.prefix(12)) + "…")
                }
                Section("关于") {
                    LabeledRow("农小秘", "iOS 版 v1.0")
                    LabeledRow("协议", "v37(uuid身份证 + sVer权威版本)")
                }
                Section {
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogoutConfirm) {
                ConfirmationDialog("退出登录?\n(本机数据保留, 重新登录后可继续同步)",
                                   isPresented: $showLogoutConfirm) {
                    appState.doLogout()
                    dismiss()
                }
            }
        }
    }
}

// 统计
struct StatsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("农事") {
                    LabeledRow("记录总数", "\(appState.db.listRecords().count)")
                    LabeledRow("地块数", "\(appState.db.listPlots().count)")
                    LabeledRow("总面积", String(format: "%.1f 亩",
                        appState.db.listPlots().reduce(0.0) { $0 + $1.area }))
                }
                Section("账本") {
                    let leds = appState.db.listLedger()
                    LabeledRow("收入", String(format: "%.0f 元",
                        leds.filter { $0.kind == "收" }.reduce(0.0) { $0 + $1.amount }))
                    LabeledRow("支出", String(format: "%.0f 元",
                        leds.filter { $0.kind == "支" }.reduce(0.0) { $0 + $1.amount }))
                }
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
