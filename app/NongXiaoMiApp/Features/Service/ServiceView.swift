import SwiftUI
import NongXiaoMiCore

// MARK: - 服务(对应安卓版"服务"占位页: 卖果/服务商等新板块, 功能陆续上线)

struct ServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "storefront")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("期待上线")
                    .font(.largeTitle).bold()
                    .foregroundColor(.green)
                Text("卖果、服务商等服务功能陆续上线")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .navigationTitle("服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
