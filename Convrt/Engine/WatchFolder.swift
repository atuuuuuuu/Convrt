import Foundation

// MARK: - Rules

/// "Convert every new file that lands in this folder to this format."
struct WatchRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var folder: String          // path
    var format: String          // OutputFormat.rawValue
    var enabled = true
}

extension Notification.Name {
    /// Posted by Settings after the watch rules change.
    static let watchRulesChanged = Notification.Name("convrt.watchRulesChanged")
}

enum WatchRuleStore {
    static let key = "watchRules"

    static func load(defaults: UserDefaults = .standard) -> [WatchRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WatchRule].self, from: data)) ?? []
    }

    static func save(_ rules: [WatchRule], defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(rules), forKey: key)
    }
}

// MARK: - Which files count, and when a file is "finished arriving"

enum WatchFilter {
    private static let partialSuffixes = [".crdownload", ".download", ".part", ".partial", ".tmp", ".temp",
                                          ".opdownload", ".filepart", ".aria2", ".!ut"]

    /// Hidden files, lock files and the half-written files browsers and copiers leave behind.
    static func shouldIgnore(name: String) -> Bool {
        let n = name.lowercased()
        if n.hasPrefix(".") || n.hasPrefix("~$") { return true }
        return partialSuffixes.contains { n.hasSuffix($0) }
    }
}

struct FileStamp: Equatable {
    let size: Int
    let modified: Date
}

/// A file is "settled" when it looks identical on two polls in a row, so a download or copy still in progress is left alone.
/// Paths are compared in canonical form, so /var/x and /private/var/x (or a symlinked folder) are the same file.
struct SettleTracker {
    private var seen = Set<String>()                 // already handled, or present before watching began
    private var pending = [String: FileStamp]()

    private static func key(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    /// Files that are already there when watching starts are never touched.
    mutating func seed(_ urls: [URL]) { seen.formUnion(urls.map(Self.key)) }

    /// Files Convrt itself just wrote.
    mutating func ignore(_ urls: [URL]) { seen.formUnion(urls.map(Self.key)) }

    /// Feed it a snapshot of the folder; it returns the files that have just finished arriving.
    mutating func observe(_ current: [URL: FileStamp]) -> [URL] {
        var byKey: [String: (url: URL, stamp: FileStamp)] = [:]
        for (url, stamp) in current { byKey[Self.key(url)] = (url, stamp) }

        seen.formIntersection(byKey.keys)                    // a file that leaves can be processed again if it returns
        pending = pending.filter { byKey.keys.contains($0.key) }
        var settled: [URL] = []
        for (key, item) in byKey.sorted(by: { $0.key < $1.key }) where !seen.contains(key) {
            if pending[key] == item.stamp {
                settled.append(item.url)
                seen.insert(key)
                pending[key] = nil
            } else {
                pending[key] = item.stamp
            }
        }
        return settled
    }
}

// MARK: - The watcher

/// Polls each enabled rule's folder every few seconds. Main thread for `apply`/`tick`; conversions run on a background queue.
final class WatchFolderService {
    typealias Convert = (URL, OutputFormat) -> ConversionSummary

    /// Automatic conversions never trash originals, whatever "move the original to the Trash" says for manual use.
    static let defaultConvert: Convert = { url, format in
        Converter.convert(urls: [url], to: format, keepOriginals: true)
    }

    private struct State {
        var rule: WatchRule
        var tracker = SettleTracker()
        var busyStems = Set<String>()
    }

    private let interval: TimeInterval
    private let convert: Convert
    private let onResult: (ConversionSummary, WatchRule) -> Void
    private let queue = DispatchQueue(label: "convrt.watch-folders", qos: .utility)
    private var states: [UUID: State] = [:]
    private var timer: Timer?

    init(interval: TimeInterval = 3,
         convert: @escaping Convert = WatchFolderService.defaultConvert,
         onResult: @escaping (ConversionSummary, WatchRule) -> Void = { _, _ in }) {
        self.interval = interval
        self.convert = convert
        self.onResult = onResult
    }

    // MARK: Configuration

    /// Starts watching new rules (existing files are left alone), stops removed or disabled ones.
    func apply(rules: [WatchRule]) {
        let wanted = rules.filter(\.enabled)
        let ids = Set(wanted.map(\.id))
        states = states.filter { ids.contains($0.key) }
        for rule in wanted {
            if let existing = states[rule.id], existing.rule.folder == rule.folder {
                states[rule.id]?.rule = rule                     // only the format changed
            } else {
                var state = State(rule: rule)
                state.tracker.seed(Array(Self.snapshot(of: URL(fileURLWithPath: rule.folder, isDirectory: true)).keys))
                states[rule.id] = state
            }
        }
    }

    func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Polling

    func tick() {
        for id in Array(states.keys) { poll(id) }
    }

    private func poll(_ id: UUID) {
        guard var state = states[id] else { return }
        let folder = URL(fileURLWithPath: state.rule.folder, isDirectory: true)
        let settled = state.tracker.observe(Self.snapshot(of: folder))
        states[id] = state
        guard let format = OutputFormat(rawValue: state.rule.format) else { return }

        for url in settled {
            let stem = url.deletingPathExtension().lastPathComponent
            guard !state.busyStems.contains(stem),                       // probably the output of a conversion in progress
                  FormatCatalog.formats(for: [url]).contains(format) else { continue }
            states[id]?.busyStems.insert(stem)
            queue.async { [weak self] in
                guard let self else { return }
                let summary = self.convert(url, format)
                DispatchQueue.main.async { self.finished(id, stem: stem, summary: summary) }
            }
        }
    }

    private func finished(_ id: UUID, stem: String, summary: ConversionSummary) {
        guard states[id] != nil else { return }
        states[id]?.tracker.ignore(summary.outputs)
        states[id]?.busyStems.remove(stem)
        if let rule = states[id]?.rule { onResult(summary, rule) }
    }

    /// Calls `done` on the main thread after every conversion queued so far has finished and reported.
    func waitUntilIdle(_ done: @escaping () -> Void) {
        queue.async { DispatchQueue.main.async(execute: done) }
    }

    private static func snapshot(of folder: URL) -> [URL: FileStamp] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return [:] }
        var result: [URL: FileStamp] = [:]
        for url in items where !WatchFilter.shouldIgnore(name: url.lastPathComponent) {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            result[url] = FileStamp(size: v.fileSize ?? 0, modified: v.contentModificationDate ?? .distantPast)
        }
        return result
    }
}
