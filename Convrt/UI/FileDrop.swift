import AppKit
import UniformTypeIdentifiers

enum FileDrop {
    /// Reads the file URLs out of SwiftUI drop providers. `completion` runs on the main thread.
    static func urls(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var found: [(Int, URL)] = []
        let lock = NSLock()
        for (index, provider) in providers.enumerated() where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { lock.lock(); found.append((index, url)); lock.unlock() }
            }
        }
        group.notify(queue: .main) { completion(found.sorted { $0.0 < $1.0 }.map(\.1)) }
    }
}
