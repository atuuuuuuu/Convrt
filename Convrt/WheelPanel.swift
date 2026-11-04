import AppKit

/// Borderless, transparent, non-activating panel that floats above everything.
final class WheelPanel: NSPanel {
    init(contentView view: NSView) {
        let size = WheelMetrics.panelSize
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                 // the SwiftUI view draws its own soft shadows
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false        // must be false so the wedges can receive drops
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
