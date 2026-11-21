import SwiftUI
import PhotosUI
import NongXiaoMiCore

// MARK: - 日常观察(对应 DailyNoteActivity/DailyHistoryActivity: 一天多条+天气/照片/星标)

struct DailyNoteView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var weather = ""
    @State private var star = false
    @State private var photos: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextEditor(text: $content)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .autocorrectionDisabled(false)
                TextField("天气(如 晴 28℃)", text: $weather)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    PhotosPicker(selection: $photoData, maxSelectionCount: 4,
                                  matching: .images) {
                        Label("照片", systemImage: "camera")
                    }
                    Spacer()
                    Toggle("重点提醒", isOn: $star)
                }
                Button {
                    save()
                } label: {
                    Text("保存观察").bold()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.isEmpty)
                Spacer()
            }
            .padding()
            .navigationTitle("日常观察")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("历史") { showHistory = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showHistory) { DailyHistoryView() }
            .onChange(of: photoData) { _ in loadPhotos() }
        }
    }

    @State private var showHistory = false
    @State private var photoData: [PhotosPickerItem] = []

    // 照片 → 本地文件(;分隔存photos列)
    private func loadPhotos() {
        let items = photoData
        Task {
            for it in items {
                if let data = try? await it.loadTransferable(type: Data.self),
                   let p = PhotoStore.save(data) { photos.append(p) }
            }
        }
    }

    private func save() {
        let ts = ISO8601TimeFormat.fullFormatter.string(from: Date())
        let date = String(ts.prefix(10))
        appState.db.addDailyNote(date: date, content: content,
                                 photos: photos.joined(separator: ";"),
                                 ts: ts, weather: weather, gps: "",
                                 star: star)
        Task { appState.syncEngine?.tick() }
        dismiss()
    }
}

// 日常观察历史
struct DailyHistoryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(appState.db.listDailyNotes().reversed(), id: \.ts) { n in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(n.date)
                        if n.star > 0 {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                        }
                        Spacer()
                        if !n.weather.isEmpty {
                            Text(n.weather).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .font(.subheadline)
                    Text(n.content)
                    if !n.photos.isEmpty {
                        HStack {
                            ForEach(n.photos.split(separator: ";").map(String.init),
                                    id: \.self) { p in
                                if let img = UIImage(contentsOfFile: p) {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("观察历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
