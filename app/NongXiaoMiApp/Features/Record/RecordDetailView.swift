import SwiftUI
import NongXiaoMiCore

// MARK: - 记录详情(对应 RecordDetailActivity.java: 字段+品项照片+删除/修改申请)

struct RecordDetailView: View {
    let recordId: Int64
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showPhoto: PhotoRef?

    private var rows: [RecordRow] { appState.db.listRecords() }
    private var row: RecordRow? { rows.first { $0.id == recordId } }
    private var items: [RecordItem] { appState.db.listItems(recordId: recordId) }

    var body: some View {
        if let row {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(row.op) · \(row.plot)")
                            .font(.title2).bold()
                        LabeledRow("日期", row.date)
                        LabeledRow("作物", row.crop)
                        LabeledRow("品项", row.pesticide)
                        LabeledRow("用量", row.dose)
                        LabeledRow("方式", row.method)
                        LabeledRow("天气", row.weather)
                        LabeledRow("天气备注", row.weatherNote)
                        LabeledRow("备注", row.note)
                        LabeledRow("保存于", row.ts)

                        // 品项明细+照片
                        if !items.isEmpty {
                            Text("品项明细").font(.headline)
                            ForEach(items, id: \.name) { it in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(it.name)
                                        if !it.dose.isEmpty {
                                            Text(it.dose).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if !it.photoPath.isEmpty {
                                        if let img = UIImage(contentsOfFile: it.photoPath) {
                                            Image(uiImage: img)
                                                .resizable().scaledToFill()
                                                .frame(width: 64, height: 64)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .onTapGesture { showPhoto = PhotoRef(path: it.photoPath) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("记录详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("删除", role: .destructive) { showDeleteConfirm = true }
                    }
                }
                .confirmationDialog("删除这条记录?\n将同步删除到所有设备",
                                    isPresented: $showDeleteConfirm) {
                    Button("删除", role: .destructive) { delete() }
                    Button("取消", role: .cancel) {}
                }
                .fullScreenCover(item: $showPhoto) { ref in
                    if let img = UIImage(contentsOfFile: ref.path) {
                        PhotoFullScreen(image: img) { dismissPhoto() }
                    }
                }
            }
        }
    }

    private func delete() {
        guard let row else { return }
        // 本地删除 + 墓碑(删除传播到其它设备)
        if !row.hash.isEmpty {
            appState.db.addTombstone(kind: "record", uuid: row.hash)
        }
        appState.db.deleteRecord(row.id)
        Task { appState.syncEngine?.tick() }
        dismiss()
    }

    private func dismissPhoto() {
        showPhoto = nil
    }
}

struct LabeledRow: View {
    let label: String, value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundColor(.secondary).frame(width: 72, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
        }
        .font(.subheadline)
    }
}

struct PhotoFullScreen: View {
    let image: UIImage
    let onDismiss: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable().scaledToFit()
            VStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle).foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 30)
            }
        }
        .onTapGesture(perform: onDismiss)
    }
}

// 全屏照片引用(String不满足Identifiable, fullScreenCover(item:)要求)
struct PhotoRef: Identifiable {
    let path: String
    var id: String { path }
}
