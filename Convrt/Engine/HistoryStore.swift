import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let title: String          // "PNG", "Compress", "Zip", ...
    let outputs: [URL]
}

/// The last few results, so "Undo" can put them in the Trash. Stored on this Mac only
/// (~/Library/Application Support/Convrt/history.json) and cleared from the menu. Main thread only.
final class HistoryStore {
    struct UndoResult: Equatable {
        var trashed = 0, missing = 0, failed = 0
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Convrt/history.json")
    }

    static let shared = HistoryStore(fileURL: defaultFileURL)

    private let fileURL: URL
    private let limit: Int
    private let trash: (URL) throws -> Void
    private(set) var entries: [HistoryEntry] = []

    init(fileURL: URL, limit: Int = 20,
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.fileURL = fileURL
        self.limit = limit
        self.trash = trash
        load()
    }

    /// Runs that produced no new files (AirDrop, Copy Path, ...) are not recorded.
    func record(title: String, outputs: [URL]) {
        guard !outputs.isEmpty else { return }
        entries.insert(HistoryEntry(id: UUID(), date: Date(), title: title, outputs: outputs), at: 0)
        entries = Array(entries.prefix(limit))
        save()
    }

    /// Moves the entry's output files to the Trash. Originals are never touched: only files Convrt made are listed.
    func undo(_ id: UUID) -> UndoResult {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return UndoResult() }
        var result = UndoResult()
        var leftOver: [URL] = []
        for url in entries[index].outputs {
            guard FileManager.default.fileExists(atPath: url.path) else { result.missing += 1; continue }
            do { try trash(url); result.trashed += 1 }
            catch { result.failed += 1; leftOver.append(url) }
        }
        if leftOver.isEmpty {
            entries.remove(at: index)
        } else {
            let old = entries[index]
            entries[index] = HistoryEntry(id: old.id, date: old.date, title: old.title, outputs: leftOver)
        }
        save()
        return result
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
