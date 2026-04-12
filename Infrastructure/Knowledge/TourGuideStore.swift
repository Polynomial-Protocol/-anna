import Foundation

struct TourGuide: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var fileName: String
    var addedAt: Date

    var displayName: String {
        name.isEmpty ? fileName : name
    }
}

actor TourGuideStore {
    private let directory: URL
    private let manifestURL: URL
    private var guides: [TourGuide] = []

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("Anna/tour-guides", isDirectory: true)
        manifestURL = directory.appendingPathComponent("manifest.json")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([TourGuide].self, from: data) {
            guides = decoded
        }
    }

    func allGuides() -> [TourGuide] {
        guides.sorted { $0.addedAt > $1.addedAt }
    }

    func importFile(at sourceURL: URL) throws -> TourGuide {
        let fileName = sourceURL.lastPathComponent
        let destURL = directory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let name = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized

        let guide = TourGuide(id: UUID(), name: name, fileName: fileName, addedAt: Date())
        guides.append(guide)
        saveManifest()
        return guide
    }

    func addGuide(name: String, content: String) throws -> TourGuide {
        let sanitized = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9\\-]", with: "", options: .regularExpression)
        let fileName = "\(sanitized).txt"
        let fileURL = directory.appendingPathComponent(fileName)

        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let guide = TourGuide(id: UUID(), name: name, fileName: fileName, addedAt: Date())
        guides.append(guide)
        saveManifest()
        return guide
    }

    func removeGuide(_ guide: TourGuide) {
        let fileURL = directory.appendingPathComponent(guide.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        guides.removeAll { $0.id == guide.id }
        saveManifest()
    }

    func loadContent(for guide: TourGuide) -> String? {
        let fileURL = directory.appendingPathComponent(guide.fileName)
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func guideByID(_ id: UUID) -> TourGuide? {
        guides.first { $0.id == id }
    }

    func guideByID(_ idString: String) -> TourGuide? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return guideByID(uuid)
    }

    // MARK: - Persistence

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([TourGuide].self, from: data) else { return }
        guides = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(guides) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
