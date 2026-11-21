import SwiftUI
import PhotosUI
import NongXiaoMiCore

// MARK: - 地块详情(对应 PlotDetailActivity.java: 记录列表+面积+圈定图)
// MARK: - 地块管理(对应 PlotActivity.java: 增删地块/圈地)

struct PlotDetailView: View {
    let plotName: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var plot: FarmDb.PlotRow? {
        appState.db.listPlots().first { $0.name == plotName }
    }
    private var records: [FarmDb.RecordRow] {
        appState.db.listRecords().filter { $0.plot == plotName }
    }
    private var ledgers: [FarmDb.LedgerRow] {
        appState.db.listLedger().filter { $0.plot == plotName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let plot {
                        HStack(spacing: 12) {
                            if !plot.thumb.isEmpty, let img = UIImage(contentsOfFile: plot.thumb) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            VStack(alignment: .leading) {
                                Text(plot.name).font(.headline)
                                Text(String(format: "%.1f 亩", plot.area))
                                    .font(.subheadline).foregroundColor(.secondary)
                                if !plot.center.isEmpty {
                                    Text(plot.center)
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }

                    Text("农事记录 \(records.count) 条").font(.headline)
                    if records.isEmpty {
                        Text("暂无记录").foregroundColor(.secondary)
                    } else {
                        ForEach(records.reversed(), id: \.id) { r in
                            RecordListRow(r: r)
                                .onTapGesture {
                                    showRecord = r.id
                                }
                        }
                    }

                    Text("收支 \(ledgers.count) 笔").font(.headline)
                    ForEach(ledgers.reversed(), id: \.id) { LedgerRowView(l: $0) }
                }
                .padding()
            }
            .navigationTitle(plotName)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $showRecord) { id in
                RecordDetailView(recordId: id)
            }
        }
    }

    @State private var showRecord: Int64?

    // sheet(item:) 需要 Identifiable
    private extension Int64 {
        var id: Int64 { self }
    }
}

struct RecordListRow: View {
    let r: FarmDb.RecordRow
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(r.op)\(r.pesticide.isEmpty ? "" : " · " + r.pesticide)")
                Text(r.date + (r.crop.isEmpty ? "" : " · " + r.crop))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !r.ts.isEmpty {
                Text(String(r.ts.prefix(10)))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// 地块管理
struct PlotManageView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.db.listPlots(), id: \.id) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(String(format: "%.1f 亩", p.area))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("删", role: .destructive) {
                            deletePlot(p)
                        }
                    }
                }
            }
            .navigationTitle("地块管理")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddPlotView() }
        }
    }

    private func deletePlot(_ p: FarmDb.PlotRow) {
        appState.db.deletePlot(p.name)
        appState.db.addTombstone(kind: "plot", uuid: UuidCanon.plotUuid(name: p.name))
        Task { appState.syncEngine?.tick() }
    }
}

// 新建地块
struct AddPlotView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var area = ""
    @State private var polygon = ""
    @State private var center = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("地块名(如 树合一号池)", text: $name)
                TextField("面积(亩)", text: $area)
                    .keyboardType(.decimalPad)
                TextField("边界(经纬度串, 可选)", text: $polygon)
                TextField("中心(经纬度, 可选)", text: $center)
            }
            .navigationTitle("新建地块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        appState.db.addPlot(name: name, polygon: polygon,
                            area: Double(area) ?? 0, thumb: "", center: center)
        Task { appState.syncEngine?.tick() }
        dismiss()
    }
}
