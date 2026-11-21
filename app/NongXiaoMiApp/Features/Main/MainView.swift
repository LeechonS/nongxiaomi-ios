import SwiftUI
import NongXiaoMiCore

// MARK: - 首页看板(对应 MainActivity.java: 地块卡片+间隔提醒+统计盒+快捷记一笔)

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAdd = false
    @State private var showLedger = false
    @State private var showPlots = false
    @State private var showSync = false
    @State private var showMine = false
    @State private var showStats = false
    @State private var showDaily = false
    @State private var showPlotDetail: PlotSheet?

    private var plots: [FarmDb.PlotRow] { appState.db.listPlots() }
    private var marks: [FarmDb.MarkRow] { appState.db.listMarks() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    syncBar
                    quickActions
                    statBoxes
                    Text("地块").font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if plots.isEmpty {
                        Text("还没有地块, 先建一个")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(plots, id: \.id) { p in
                            PlotCard(plot: p)
                                .onTapGesture {
                                    showPlotDetail = PlotSheet(name: p.name)
                                }
                        }
                    }
                    markReminders
                }
                .padding()
            }
            .navigationTitle("农小秘")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showSync = true } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    Button { showMine = true } label: { Image(systemName: "person.circle") }
                }
            }
            .sheet(isPresented: $showAdd) { AddView() }
            .sheet(isPresented: $showLedger) { LedgerView() }
            .sheet(isPresented: $showPlots) { PlotManageView() }
            .sheet(isPresented: $showSync) { SyncView() }
            .sheet(isPresented: $showMine) { MineView() }
            .sheet(isPresented: $showStats) { StatsView() }
            .sheet(isPresented: $showDaily) { DailyNoteView() }
            .sheet(item: $showPlotDetail) { sheet in
                PlotDetailView(plotName: sheet.name)
            }
        }
    }

    // 同步状态条
    private var syncBar: some View {
        HStack {
            Image(systemName: "icloud")
            Text(appState.lastSyncAt.map {
                "上次同步 " + ISO8601TimeFormat.short($0)
            } ?? "未同步")
            if !appState.syncMessage.isEmpty {
                Text(appState.syncMessage).lineLimit(1)
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    // 统计盒(对应 DashBoxView: 记录数/账本/地块面积)
    private var statBoxes: some View {
        HStack(spacing: 10) {
            DashBox(title: "农事记录",
                    value: "\(appState.db.listRecords().count) 条",
                    icon: "leaf")
            DashBox(title: "收支账本",
                    value: money(appState.db.listLedger()),
                    icon: "yensign.circle")
            DashBox(title: "地块",
                    value: "\(plots.count) 块 \(area(plots))亩",
                    icon: "map")
        }
    }

    // 间隔提醒(对应 marks: 距某地块某操作几天)
    private var markReminders: some View {
        Group {
            if !marks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("提醒").font(.headline)
                    ForEach(marks, id: \.self) { m in
                        HStack {
                            Image(systemName: "bell")
                                .foregroundColor(.orange)
                            Text("\(m.plot) · \(m.op)")
                            Spacer()
                            Text(daysSince(m.date) + " 天前")
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    // 快捷入口(对应Android首页底部按钮)
    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickButton(title: "记一笔", icon: "square.and.pencil") { showAdd = true }
            QuickButton(title: "记账", icon: "yensign.circle") { showLedger = true }
            QuickButton(title: "地块", icon: "map") { showPlots = true }
            QuickButton(title: "观察", icon: "sun.max") { showDaily = true }
            QuickButton(title: "统计", icon: "chart.bar") { showStats = true }
        }
    }

    private func money(_ leds: [FarmDb.LedgerRow]) -> String {
        let sum = leds.reduce(0.0) { $0 + ($1.kind == "收" ? $1.amount : -$1.amount) }
        return String(format: "%.0f 元(净)", sum)
    }

    private func area(_ plots: [FarmDb.PlotRow]) -> String {
        String(format: "%.1f", plots.reduce(0.0) { $0 + $1.area })
    }

    private func daysSince(_ date: String) -> Int {
        guard let f = ISO8601TimeFormat.dateFormatter, let d = f.date(from: date) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(d) / 86400))
    }
}

// 地块详情sheet的Identifiable包装(String本身不符合Identifiable)
struct PlotSheet: Identifiable {
    let name: String
    var id: String { name }
}

// 地块卡片
struct PlotCard: View {
    let plot: FarmDb.PlotRow

    var body: some View {
        HStack(spacing: 12) {
            if !plot.thumb.isEmpty {
                if let img = UIImage(contentsOfFile: plot.thumb) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "map").foregroundColor(.green))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(plot.name).font(.headline)
                Text("\(String(format: "%.1f", plot.area)) 亩")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct QuickButton: View {
    let title: String, icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
    }
}

struct DashBox: View {
    let title: String, value: String, icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// 简易日期工具
enum ISO8601TimeFormat {
    static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    static let dateFormatter: DateFormatter? = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func short(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
