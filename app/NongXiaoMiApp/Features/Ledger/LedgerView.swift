import SwiftUI
import PhotosUI
import NongXiaoMiCore

// MARK: - 收支账本(对应 LedgerActivity/LedgerBookActivity: 收支列表+记一笔账)

struct LedgerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var month = ""

    var body: some View {
        NavigationStack {
            List {
                if !month.isEmpty {
                    Section {
                        Text("本月: 收 \(sum("收", month)) 元 · 支 \(sum("支", month)) 元")
                            .font(.subheadline)
                    }
                }
                Section {
                    ForEach(appState.db.listLedger().reversed(), id: \.id) { l in
                        LedgerRowView(l: l)
                    }
                }
            }
            .navigationTitle("收支账本")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddLedgerView() }
        }
    }

    private func sum(_ kind: String, _ m: String) -> String {
        String(format: "%.0f", appState.db.listLedger()
            .filter { $0.kind == kind && ($0.date.hasPrefix(m)) }
            .reduce(0.0) { $0 + $1.amount })
    }
}

struct LedgerRowView: View {
    let l: FarmDb.LedgerRow
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(l.kind) · \(l.category)")
                Text("\(l.date)\(l.plot.isEmpty ? "" : " · " + l.plot)")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text((l.kind == "收" ? "+" : "-") + String(format: "%.0f", l.amount))
                .foregroundColor(l.kind == "收" ? .green : .red)
                .font(.headline)
        }
    }
}

// 记一笔账
struct AddLedgerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var date = ""
    @State private var kind = "支"
    @State private var category = "种子"
    @State private var amount = ""
    @State private var plot = ""
    @State private var note = ""
    @State private var photoPath = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("日期", selection: Binding(
                    get: { date.isEmpty ? Date() : ISO8601TimeFormat.dateFormatter?.date(from: date) ?? Date() },
                    set: { date = ISO8601TimeFormat.dateFormatter?.string(from: $0) ?? "" }),
                    displayedComponents: .date)
                Picker("类型", selection: $kind) {
                    Text("支出").tag("支"); Text("收入").tag("收")
                }
                TextField("类别(如 种子/农药/雇工/售果)", text: $category)
                TextField("金额", text: $amount)
                    .keyboardType(.decimalPad)
                Picker("地块", selection: $plot) {
                    Text("不关联").tag("")
                    ForEach(appState.db.listPlots().map { $0.name }, id: \.self) {
                        Text($0)
                    }
                }
                TextField("备注", text: $note)
                PhotosPicker(selection: $photoData, matching: .images) {
                    Label(photoPath.isEmpty ? "发票照片(可选)" : "已选照片", systemImage: "camera")
                }
            }
            .navigationTitle("记一笔账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(amount.isEmpty)
                }
            }
            .onChange(of: photoData) { _ in loadPhoto() }
        }
    }

    @State private var photoData: [PhotosPickerItem] = []

    // 发票照片 → 本地文件
    private func loadPhoto() {
        let items = photoData
        Task {
            for it in items {
                if let data = try? await it.loadTransferable(type: Data.self),
                   let p = PhotoStore.save(data) { photoPath = p }
            }
        }
    }

    private func save() {
        let ts = ISO8601TimeFormat.fullFormatter.string(from: Date())
        appState.db.addLedger(date: date, kind: kind, category: category,
                              amount: Double(amount) ?? 0, plot: plot,
                              note: note, photo: photoPath.isEmpty ? nil : photoPath,
                              ts: ts, uuid: UUID().uuidString)
        Task { appState.syncEngine?.tick() }
        dismiss()
    }
}
