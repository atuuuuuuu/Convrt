import Foundation

/// Which wheel is showing and which slice is highlighted. Pure logic, no UI.
struct WheelState {
    let urls: [URL]
    private(set) var kind: WheelKind
    private(set) var items: [WheelItem]
    /// Index into `items`. Set by mouse hover as well as by `step`.
    var highlighted: Int?
    /// Wheels that have at least one item for the dragged files, in cycling order.
    let availableKinds: [WheelKind]

    var highlightedItem: WheelItem? {
        guard let i = highlighted, items.indices.contains(i) else { return nil }
        return items[i]
    }

    init(urls: [URL], start: WheelKind = .convert) {
        self.urls = urls
        availableKinds = WheelKind.allCases.filter { !WheelCatalog.items(for: $0, urls: urls).isEmpty }
        let first = availableKinds.contains(start) ? start : (availableKinds.first ?? start)
        kind = first
        items = WheelCatalog.items(for: first, urls: urls)
        highlighted = nil
    }

    /// Option: next wheel that has items. Does nothing when there is no other wheel.
    mutating func cycle() {
        guard availableKinds.count > 1, let at = availableKinds.firstIndex(of: kind) else { return }
        show(availableKinds[(at + 1) % availableKinds.count])
    }

    /// Command / Control: go straight to a wheel, ignored if it has nothing to offer.
    mutating func jump(to target: WheelKind) {
        guard availableKinds.contains(target), target != kind else { return }
        show(target)
    }

    /// Scroll / arrow keys: move the highlight, wrapping at both ends.
    mutating func step(_ delta: Int) {
        highlighted = Self.nextIndex(current: highlighted, delta: delta, count: items.count) ?? highlighted
    }

    /// The stepping rule on its own: from nothing, start at the first (forward) or last (backward) slice; wrap at the ends.
    static func nextIndex(current: Int?, delta: Int, count: Int) -> Int? {
        guard count > 0, delta != 0 else { return current }
        guard let current else { return delta > 0 ? 0 : count - 1 }
        return (((current + delta) % count) + count) % count
    }

    private mutating func show(_ target: WheelKind) {
        kind = target
        items = WheelCatalog.items(for: target, urls: urls)
        highlighted = nil
    }
}
