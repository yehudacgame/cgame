import Foundation

final class ExtLogger {
    static let shared = ExtLogger()

    private let queue = DispatchQueue(label: "com.cgameapp.extension.logger", qos: .utility)
    private let appGroupId = "group.com.cgame.shared"

    private func logURL() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return nil
        }
        let debugDir = container.appendingPathComponent("Debug", isDirectory: true)
        if !FileManager.default.fileExists(atPath: debugDir.path) {
            try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
        }
        return debugDir.appendingPathComponent("error.log")
    }

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[EXT] \(timestamp) \(message)\n"
        queue.async {
            guard let url = self.logURL() else { return }
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: url)
                }
            }
        }
    }
}


