import Foundation

/// The files sitting on the floating shelf.
final class ShelfModel: ObservableObject {
    @Published private(set) var urls: [URL] = []

    private func key(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    /// Keeps order, skips duplicates and files that don't exist.
    func add(_ new: [URL]) {
        for url in new where FileManager.default.fileExists(atPath: url.path) {
            if !urls.contains(where: { key($0) == key(url) }) { urls.append(url) }
        }
    }

    func remove(_ url: URL) { urls.removeAll { key($0) == key(url) } }

    func clear() { urls = [] }

    /// Forgets files that were deleted or moved away since they were added.
    func pruneMissing() { urls = urls.filter { FileManager.default.fileExists(atPath: $0.path) } }
}

/// The Drop Zone window's state: what was dropped and which wheel is showing.
final class DropZoneModel: ObservableObject {
    @Published private(set) var urls: [URL] = []
    @Published private(set) var kind: WheelKind = .convert

    var availableKinds: [WheelKind] { WheelState(urls: urls).availableKinds }
    var items: [WheelItem] { WheelCatalog.items(for: kind, urls: urls) }

    private func key(_ url: URL) -> String { url.resolvingSymlinksInPath().path }

    /// Adds dropped files (no duplicates) and keeps the current wheel if it still has something to offer.
    func ingest(_ new: [URL]) {
        for url in new where !urls.contains(where: { key($0) == key(url) }) { urls.append(url) }
        let available = availableKinds
        if !available.contains(kind) { kind = available.first ?? .convert }
    }

    func select(_ k: WheelKind) {
        if availableKinds.contains(k) { kind = k }
    }

    func clear() {
        urls = []
        kind = .convert
    }
}
