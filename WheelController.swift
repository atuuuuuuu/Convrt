import AppKit
import SwiftUI

final class WheelController {
    let model = WheelModel()
    private let panel: WheelPanel

    /// Called when files are dropped on a wedge.
    var onConvert: ((OutputFormat, [URL]) -> Void)?

    init() {
        let hosting = NSHostingView(rootView: RadialWheelView(model: model))
        let container = WheelDropView(hosting: hosting)
        panel = WheelPanel(contentView: container)
        container.controller = self
    }

    // MARK: - Show / hide

    func show(near point: NSPoint, urls: [URL]) {
        let formats = FormatCatalog.formats(for: urls)
        model.formats = formats
        model.message = formats.isEmpty ? "Can’t convert this type" : nil

        position(near: point)
        model.highlighted = nil
        model.visible = false
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                self?.model.visible = true
            }
        }
        updateCursor(point)
    }

    func hide() {
        guard panel.isVisible else { return }
        withAnimation(.easeIn(duration: 0.12)) { model.visible = false }
        model.highlighted = nil

        // Wait a moment so a drop that is still being delivered isn't cut off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - Hit testing

    private func wedgeIndex(dx: CGFloat, dy: CGFloat) -> Int? {
        let count = model.formats.count
        guard count > 0 else { return nil }
        let dist = hypot(dx, dy)
        guard dist >= WheelMetrics.innerRadius && dist <= WheelMetrics.outerRadius + 12 else { return nil }

        var deg = Double(atan2(dx, dy)) * 180 / .pi     // clockwise from the top
        if deg < 0 { deg += 360 }
        let slice = 360.0 / Double(count)
        return Int(((deg + slice / 2).truncatingRemainder(dividingBy: 360)) / slice)
    }

    /// Cursor position in screen coordinates (from the global monitor).
    func updateCursor(_ point: NSPoint) {
        guard panel.isVisible else { return }
        let idx = wedgeIndex(dx: point.x - panel.frame.midX, dy: point.y - panel.frame.midY)
        if model.highlighted != idx { model.highlighted = idx }
    }

    // MARK: - Drag destination (called by WheelDropView)

    func dragMoved(to local: NSPoint, in size: CGSize) -> Bool {
        let idx = wedgeIndex(dx: local.x - size.width / 2, dy: local.y - size.height / 2)
        if model.highlighted != idx { model.highlighted = idx }
        return idx != nil
    }

    func dragLeft() { model.highlighted = nil }

    func drop(at local: NSPoint, in size: CGSize, urls: [URL]) -> Bool {
        guard let idx = wedgeIndex(dx: local.x - size.width / 2, dy: local.y - size.height / 2),
              model.formats.indices.contains(idx) else { return false }
        let format = model.formats[idx]
        hide()
        DispatchQueue.main.async { [weak self] in self?.onConvert?(format, urls) }
        return true
    }

    // MARK: - Positioning

    private func position(near point: NSPoint) {
        let size = WheelMetrics.panelSize
        var origin = NSPoint(x: point.x - size / 2, y: point.y - size / 2)

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            origin.x = min(max(origin.x, area.minX), area.maxX - size)
            origin.y = min(max(origin.y, area.minY), area.maxY - size)
        }
        panel.setFrameOrigin(origin)
    }
}
