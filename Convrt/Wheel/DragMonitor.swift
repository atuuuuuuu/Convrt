import AppKit

/// What the user can do to the open wheel besides moving the mouse.
enum WheelKey {
    case cycle, convert, tools, actions, cancel, next, previous
}

/// Watches globally for "files are being dragged while the trigger key is held".
final class DragMonitor {
    /// Called once when a file drag + trigger key becomes active.
    var onTriggerBegan: ((_ urls: [URL], _ mouseLocation: NSPoint) -> Void)?
    /// Called on every mouse move while the trigger is active.
    var onDragMoved: ((_ mouseLocation: NSPoint) -> Void)?
    /// Called when the trigger key is released or the drag ends.
    var onTriggerEnded: (() -> Void)?
    /// Option / Command / Control taps, Tab, arrows and Esc while the wheel is open.
    var onKey: ((WheelKey) -> Void)?
    /// Scroll steps while the wheel is open: +1 clockwise, -1 counter-clockwise.
    var onScroll: ((Int) -> Void)?

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
    private var lastFlags: NSEvent.ModifierFlags = []
    private var scrollAccumulator: CGFloat = 0

    // MARK: - Start / stop

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                           .flagsChanged, .scrollWheel, .keyDown]
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
            lastFlags = Self.currentFlags
            countAtMouseDown = NSPasteboard(name: .drag).changeCount
            lastCheckedCount = -1
        case .leftMouseDragged:
            if activeURLs.isEmpty { detectFileDrag() }
            evaluateTrigger()
            if triggerActive { onDragMoved?(NSEvent.mouseLocation) }
        case .leftMouseUp:
            endSession()
        case .flagsChanged:
            let now = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let pressed = now.subtracting(lastFlags)
            lastFlags = now
            evaluateTrigger()
            if triggerActive { emitKeys(for: pressed) }
        case .keyDown:
            guard triggerActive else { break }
            if let key = Self.wheelKey(forKeyCode: event.keyCode) { onKey?(key) }
        case .scrollWheel:
            guard triggerActive else { break }
            handleScroll(event)
        default:
            break
        }
    }

    private static var currentFlags: NSEvent.ModifierFlags {
        NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    /// Option cycles the wheels; Command and Control jump straight to Tools and Actions.
    /// The key that opened the wheel never doubles as a wheel key.
    static func keys(for pressed: NSEvent.ModifierFlags, trigger: NSEvent.ModifierFlags,
                     optionCycles: Bool, directJump: Bool) -> [WheelKey] {
        var result: [WheelKey] = []
        if optionCycles, pressed.contains(.option), trigger != .option { result.append(.cycle) }
        if directJump {
            if pressed.contains(.command), trigger != .command { result.append(.tools) }
            if pressed.contains(.control), trigger != .control { result.append(.actions) }
        }
        return result
    }

    private func emitKeys(for pressed: NSEvent.ModifierFlags) {
        for key in Self.keys(for: pressed, trigger: triggerModifier,
                             optionCycles: AppSettings.optionCycles, directJump: AppSettings.directJumpKeys) {
            onKey?(key)
        }
    }

    static func wheelKey(forKeyCode code: UInt16) -> WheelKey? {
        switch code {
        case 53:           return .cancel      // esc
        case 48:           return .cycle       // tab
        case 123, 126:     return .previous    // left, up
        case 124, 125:     return .next        // right, down
        default:           return nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 12 : 0.5
        scrollAccumulator += event.scrollingDeltaY
        var emitted = 0
        while abs(scrollAccumulator) >= threshold && emitted < 3 {
            let step = scrollAccumulator < 0 ? 1 : -1       // scroll down = clockwise
            onScroll?(step)
            scrollAccumulator += CGFloat(step) * threshold
            emitted += 1
        }
        if emitted == 3 { scrollAccumulator = 0 }
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
            scrollAccumulator = 0
            onTriggerBegan?(activeURLs, NSEvent.mouseLocation)
            // Option (or Command / Control) already held together with the trigger: open on that wheel.
            emitKeys(for: Self.currentFlags)
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
