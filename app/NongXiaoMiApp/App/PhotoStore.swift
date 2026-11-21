import Foundation

// MARK: - 照片本地存储(相册选择 → Application Support/photos)

enum PhotoStore {
    /// 保存图片Data到本地, 返回文件路径(失败nil)
    static func save(_ data: Data, ext: String = "jpg") -> String? {
        let dir = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("photos", isDirectory: true)
        guard let dir else { return nil }
        let name = "p_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).\(ext)"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }
}
