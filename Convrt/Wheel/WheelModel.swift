import SwiftUI

enum WheelMetrics {
    static let panelSize: CGFloat = 360   // window size (extra room for shadows)
    static let outerRadius: CGFloat = 150
    static let innerRadius: CGFloat = 58
}

/// What the SwiftUI wheel draws. `WheelController` copies its `WheelState` into this.
final class WheelModel: ObservableObject {
    @Published var items: [WheelItem] = []
    @Published var kind: WheelKind = .convert
    @Published var availableKinds: [WheelKind] = []
    @Published var message: String? = nil       // shown instead of the wheel
    @Published var highlighted: Int? = nil
    @Published var visible = false

    var highlightedLabel: String? {
        guard let i = highlighted, items.indices.contains(i) else { return nil }
        return items[i].label
    }
}
