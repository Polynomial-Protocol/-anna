import Foundation

/// Logs runtime events to disk (one file per day) and keeps an in-memory
/// buffer of recent lines for the live log viewer.
@MainActor
final class RuntimeLogger: ObservableObject {
    @Published var recentLines: [String] = []

    private let logsDir: URL
    private let maxMemoryLines = 500

    init(baseDir: URL? = nil) {
        logsDir = baseDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".anna")
            .appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    // MARK: - Write

    func log(_ message: String, tag: String = "app") {
        let rendered = "[\(Self.timestampFormatter.string(from: Date()))] [\(tag)] \(message)"
        print(rendered)

        recentLines.insert(rendered, at: 0)
        if recentLines.count > maxMemoryLines {
            recentLines.removeLast()
        }

        let fileURL = logsDir.appendingPathComponent("anna-\(Self.dayFormatter.string(from: Date())).log")
        let payload = rendered + "\n"
        guard let data = payload.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }

    // MARK: - Read

    func readLogs(for date: String, lastN: Int = 1000) -> [String] {
        let fileURL = logsDir.appendingPathComponent("anna-\(date).log")
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let lines = contents.components(separatedBy: "\n").filter { !$0.isEmpty }
        if lines.count <= lastN { return lines }
        return Array(lines.suffix(lastN))
    }

    func availableLogDates() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.lastPathComponent.hasPrefix("anna-") && $0.pathExtension == "log" }
            .compactMap { url -> String? in
                let name = url.deletingPathExtension().lastPathComponent
                return name.replacingOccurrences(of: "anna-", with: "")
            }
            .sorted(by: >)
    }

    // MARK: - Formatters

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
