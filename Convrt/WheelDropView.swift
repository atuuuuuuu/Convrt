import AppKit

/// Container view that receives the drag. Wraps the SwiftUI wheel.
final class WheelDropView: NSView {
    weak var controller: WheelController?

    init(hosting: NSView) {
        let s = WheelMetrics.panelSize
        super.init(frame: NSRect(x: 0, y: 0, width: s, height: s))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func localPoint(_ sender: NSDraggingInfo) -> NSPoint {
        convert(sender.draggingLocation, from: nil)
    }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard let controller else { return [] }
        let overWedge = controller.dragMoved(to: localPoint(sender), in: bounds.size)
        guard overWedge else { return [] }     // transparent corners and the hole don't accept drops
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : .generic
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { operation(for: sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { operation(for: sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.dragLeft() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let controller else { return false }
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        return controller.drop(at: localPoint(sender), in: bounds.size, urls: urls)
    }
}
