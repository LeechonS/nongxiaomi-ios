import SwiftUI
import PhotosUI
import NongXiaoMiCore

// MARK: - 记一笔(对应 AddActivity.java 943行: 日期/地块/作物/操作/品项明细/照片/天气)

struct AddView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var date = ""
    @State private var plot = ""
    @State private var crop = ""
    @State private var op = "打药"
    @State private var pesticide = ""
    @State private var dose = ""
    @State private var note = ""
    @State private var weather = ""
    @State private var method = ""
    @State private var weatherNote = ""
    @State private var photoPaths: [String] = []
    @State private var items: [ItemDraft] = []
    @State private var busy = false
    @State private var photoData: [PhotosPickerItem] = []

    struct ItemDraft: Identifiable {
        let id = UUID()
        var name = ""
        var dose = ""
        var note = ""
    }

    private var plots: [String] {
        appState.db.listPlots().map { $0.name }
    }

    var body: some View {
        NavigationStack {
            // Form内容独立成计算属性: 让类型错误暴露在自己的准确位置
            formContent
                .navigationTitle("记一笔")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }
                            .disabled(busy || plot.isEmpty)
                    }
                }
                .onChange(of: photoData) { _ in loadPhotos() }
        }
    }

    private var formContent: some View {
        Form {
            Section("基础") {
                DatePicker("日期", selection: Binding(
                    get: { date.isEmpty ? Date() : ISO8601TimeFormat.dateFormatter?.date(from: date) ?? Date() },
                    set: { date = ISO8601TimeFormat.dateFormatter?.string(from: $0) ?? "" }),
                    displayedComponents: .date)
                if !plots.isEmpty {
                    Picker("地块", selection: $plot) {
                        ForEach(plots, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: plot) { _ in autoCrop() }
                } else {
                    TextField("地块(先在地块管理里建)", text: $plot)
                }
                TextField("作物", text: $crop)
                Picker("操作", selection: $op) {
                    ForEach(["打药", "施肥", "浇水", "除草", "采摘", "播种", "其他"], id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                TextField("用量/规格(如 500g)", text: $dose)
            }

            Section("品项明细(可选, 可加照片)") {
                ForEach($items) { $item in
                    VStack(spacing: 0) {
                        TextField("名称", text: $item.name)
                        TextField("用量", text: $item.dose)
                        TextField("备注", text: $item.note)
                    }
                }
                Button {
                    items.append(ItemDraft())
                } label: {
                    Label("加一项", systemImage: "plus")
                }
            }

            Section("照片(可选)") {
                PhotosPicker(selection: $photoData, maxSelectionCount: 6,
                              matching: .images) {
                    Label(photoPaths.isEmpty ? "拍照/选图" : "已选 \(photoPaths.count) 张",
                          systemImage: "camera")
                }
            }

            Section("备注") {
                TextField("备注", text: $note, axis: .vertical)
                TextField("作业方式(如 喷雾)", text: $method)
                TextField("天气(如 晴 28℃)", text: $weather)
                TextField("天气备注", text: $weatherNote)
            }
        }
    }

    // 照片选择 → 本地文件(路径挂到品项明细)
    private func loadPhotos() {
        let items = photoData
        Task {
            for it in items {
                guard let data = try? await it.loadTransferable(type: Data.self) else { continue }
                if let p = PhotoStore.save(data) { photoPaths.append(p) }
            }
        }
    }

    // 地块作物记忆: 换地块/进页面带出最近作物; 用户手输过不覆盖
    @State private var lastAutoCrop = ""
    private func autoCrop() {
        let last = appState.db.lastCropForPlot(plot)
        guard !last.isEmpty else {
            crop = ""; return
        }
        // 用户手输过(非上次自动带出值)不覆盖
        if crop == lastAutoCrop || crop.isEmpty {
            crop = last
            lastAutoCrop = last
        }
    }

    private func save() {
        busy = true
        let ts = ISO8601TimeFormat.fullFormatter.string(from: Date())
        let db = appState.db
        // 唯一uuid: 秒级"时间+地块"当身份会让同秒两条记录在池内塌成一条,
        // 且删除墓碑会连另一条一起清掉 → 保存时就地生成随机hash(不带前缀, 推送时补)
        let hash = UUID().uuidString
        let rid = db.addRecord(date: date, plot: plot, crop: crop, op: op,
                               pesticide: pesticide, dose: dose, note: note,
                               hash: hash, ts: ts, weather: weather,
                               method: method, weatherNote: weatherNote)
        // 品项+照片
        var recItems: [RecordItem] = []
        for (i, it) in items.enumerated() where !it.name.isEmpty {
            let pp = i < photoPaths.count ? photoPaths[i] : ""
            recItems.append(RecordItem(name: it.name, dose: it.dose,
                                       note: it.note, photoPath: pp))
        }
        if !recItems.isEmpty { db.addItems(recordId: rid, recItems) }
        // 间隔标记: 首页间隔框+记录打🔖记号
        if ["打药", "施肥", "浇水"].contains(op) {
            db.addMark(plot: plot, op: op, date: date, recordId: rid)
            // 清旧登记: 同身份标记重建后能重新入池(不被旧墓碑压制)
            db.clearMarkTombstone(plot: plot, op: op, date: date)
        }
        // 写后即推(fire-and-forget, 失败靠tick补推)
        Task { appState.syncEngine?.tick() }
        busy = false
        dismiss()
    }
}
