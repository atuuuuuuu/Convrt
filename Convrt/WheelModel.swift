import SwiftUI

enum WheelMetrics {
    static let panelSize: CGFloat = 360   // window size (extra room for shadows)
    static let outerRadius: CGFloat = 150
    static let innerRadius: CGFloat = 58
}

final class WheelModel: ObservableObject {
    @Published var formats: [OutputFormat] = []
    @Published var message: String? = nil       // shown instead of the wheel
    @Published var highlighted: Int? = nil
    @Published var visible = false

    var centerText: String {
        if let i = highlighted, formats.indices.contains(i) { return formats[i].label }
        return "Convert to…"
    }
}
