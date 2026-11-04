import AppKit

/// Watches globally for "files are being dragged while the trigger key is held".
final class DragMonitor {
    /// Called once when a file drag + trigger key becomes active.
    var onTriggerBegan: ((_ urls: [URL], _ mouseLocation: NSPoint) -> Void)?
    /// Called on every mouse move while the trigger is active.
    var onDragMoved: ((_ mouseLocation: NSPoint) -> Void)?
    /// Called when the trigger key is released or the drag ends.
    var onTriggerEnded: (() -> Void)?

    /// Chosen in Settings (Shift by default).
    var triggerModifier: NSEvent.ModifierFlags { AppSettings.convertTrigger.flags }

    // Counters shown in Diagnostics.
    private(set) var eventsSeen = 0
    private(set) var dragsDetected = 0
    var isRunning: Bool { monitor != nil }

    private var monitor: Any?
    private var watchdog: Timer?

    private var countAtMouseDown = 0
    private var lastCheckedCount = -1
    private var activeURLs: [URL] = []
    private var triggerActive = false

    // MARK: - Start / stop

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        AppLog.write("drag monitor started (\(monitor == nil ? "FAILED" : "ok"))")
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        endSession()
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        eventsSeen += 1
        switch event.type {
        case .leftMouseDown:
            endSession()
            countAtMouseDown = NSPasteboard(name: .drag).changeCount
            lastCheckedCount = -1
        case .leftMouseDragged:
            if activeURLs.isEmpty { detectFileDrag() }
            evaluateTrigger()
            if triggerActive { onDragMoved?(NSEvent.mouseLocation) }
        case .leftMouseUp:
            endSession()
        case .flagsChanged:
            evaluateTrigger()
        default:
            break
        }
    }

    /// A drag has started when the drag pasteboard changed since the mouse went down
    /// and it contains file URLs.
    private func detectFileDrag() {
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != countAtMouseDown, pb.changeCount != lastCheckedCount else { return }
        lastCheckedCount = pb.changeCount

        let urls = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        activeURLs = urls
        dragsDetected += 1
        AppLog.write("file drag detected: \(urls.count) item(s)")
        startWatchdog()
    }

    private func evaluateTrigger() {
        let held = NSEvent.modifierFlags.contains(triggerModifier)
        let shouldBeActive = !activeURLs.isEmpty && held

        if shouldBeActive && !triggerActive {
            triggerActive = true
            onTriggerBegan?(activeURLs, NSEvent.mouseLocation)
        } else if !shouldBeActive && triggerActive {
            triggerActive = false
            onTriggerEnded?()
        }
    }

    // MARK: - Cleanup

    /// Global monitors don't reliably see the mouse-up that ends a drag session,
    /// so we also poll the real button state while a file drag is active.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            if NSEvent.pressedMouseButtons & 1 == 0 { self?.endSession() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func endSession() {
        watchdog?.invalidate()
        watchdog = nil
        activeURLs = []
        if triggerActive {
            triggerActive = false
            onTriggerEnded?()
        }
    }
}
