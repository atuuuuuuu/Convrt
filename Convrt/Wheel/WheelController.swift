import AppKit
import SwiftUI

final class WheelController {
    let model = WheelModel()
    private let panel: WheelPanel
    private(set) var state = WheelState(urls: [])
    /// True when the highlight came from scroll or keys, so hovering away must not clear it.
    private var highlightFromKeys = false

    /// Called when the user picks a slice (drop on a wedge, or drop on the centre with a highlight).
    var onRun: ((WheelItem, [URL]) -> Void)?

    init() {
        let hosting = NSHostingView(rootView: RadialWheelView(model: model))
        let container = WheelDropView(hosting: hosting)
        panel = WheelPanel(contentView: container)
        container.controller = self
    }

    // MARK: - Show / hide

    func show(near point: NSPoint, urls: [URL]) {
        state = WheelState(urls: urls)
        highlightFromKeys = false
        publish()

        position(near: point)
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
        state.highlighted = nil
        publish()

        // Wait a moment so a drop that is still being delivered isn't cut off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.model.visible else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - Keys and scroll

    func handle(_ key: WheelKey) {
        guard panel.isVisible else { return }
        switch key {
        case .cycle:    state.cycle()
        case .convert:  state.jump(to: .convert)
        case .tools:    state.jump(to: .tools)
        case .actions:  state.jump(to: .actions)
        case .next:     state.step(1)
        case .previous: state.step(-1)
        case .cancel:   hide(); return
        }
        highlightFromKeys = true
        publish()
    }

    func scroll(steps: Int) {
        guard panel.isVisible, steps != 0 else { return }
        state.step(steps)
        highlightFromKeys = true
        publish()
    }

    // MARK: - Hover (mouse position)

    private func wedge(dx: CGFloat, dy: CGFloat) -> Int? {
        WheelHitTest.wedgeIndex(dx: dx, dy: dy, count: state.items.count,
                                inner: WheelMetrics.innerRadius, outer: WheelMetrics.outerRadius)
    }

    /// Cursor position in screen coordinates (from the global monitor).
    func updateCursor(_ point: NSPoint) {
        guard panel.isVisible else { return }
        hover(wedge(dx: point.x - panel.frame.midX, dy: point.y - panel.frame.midY))
    }

    /// Hovering a wedge highlights it. Hovering the centre or the outside keeps a scroll/key highlight.
    private func hover(_ index: Int?) {
        if let index {
            if state.highlighted != index || highlightFromKeys {
                state.highlighted = index
                highlightFromKeys = false
                publish()
            }
        } else if !highlightFromKeys, state.highlighted != nil {
            state.highlighted = nil
            publish()
        }
    }

    // MARK: - Drag destination (called by WheelDropView)

    /// True when a drop here would be accepted: over a wedge, or over the centre while something is highlighted.
    func dragMoved(to local: NSPoint, in size: CGSize) -> Bool {
        let dx = local.x - size.width / 2, dy = local.y - size.height / 2
        let idx = wedge(dx: dx, dy: dy)
        hover(idx)
        if idx != nil { return true }
        return WheelHitTest.isCentre(dx: dx, dy: dy, inner: WheelMetrics.innerRadius) && state.highlightedItem != nil
    }

    func dragLeft() { hover(nil) }

    func drop(at local: NSPoint, in size: CGSize, urls: [URL]) -> Bool {
        let dx = local.x - size.width / 2, dy = local.y - size.height / 2
        let item: WheelItem
        if let idx = wedge(dx: dx, dy: dy), state.items.indices.contains(idx) {
            item = state.items[idx]
        } else if WheelHitTest.isCentre(dx: dx, dy: dy, inner: WheelMetrics.innerRadius),
                  let highlighted = state.highlightedItem {
            item = highlighted
        } else {
            return false
        }
        hide()
        DispatchQueue.main.async { [weak self] in self?.onRun?(item, urls) }
        return true
    }

    // MARK: - Publishing and positioning

    private func publish() {
        model.items = state.items
        model.kind = state.kind
        model.availableKinds = state.availableKinds
        model.highlighted = state.highlighted
        model.message = state.availableKinds.isEmpty ? "Nothing to do with this file" : nil
    }

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
