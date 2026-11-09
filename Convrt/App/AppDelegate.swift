import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!
    private let settingsController = SettingsWindowController()
    private let dragMonitor = DragMonitor()
    private lazy var wheel = WheelController()
    private let hud = HUDController()
    private var permissionTimer: Timer?
    private var recentItem: NSMenuItem!
    private let dropZone = DropZoneController()
    private lazy var watcher = WatchFolderService(onResult: { [weak self] summary, rule in self?.watchFinished(summary, rule) })

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        if AppEnvironment.isRunningTests { return }

        #if !DEBUG
        // Shipping builds: never run two copies (two icons, two wheels).
        if otherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }
        #endif

        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupDragMonitor()   // start BEFORE any alert, because alerts block the main thread
        startWatchFolders()

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        AppLog.write("Convrt \(version) launched from \(Bundle.main.bundlePath); "
                     + "accessibility=\(PermissionManager.accessibilityGranted) "
                     + "inputMonitoring=\(PermissionManager.inputMonitoringGranted)")

        DispatchQueue.main.async { [weak self] in
            PermissionManager.check()
            self?.watchForPermissionChanges()
        }
    }

    private func otherInstanceIsRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != me }
    }

    // MARK: - Drag monitor

    private func setupDragMonitor() {
        wheel.onRun = { [weak self] item, urls in
            self?.run(item, urls)
        }
        dropZone.onRun = { [weak self] item, urls in
            self?.run(item, urls)
        }
        dragMonitor.onTriggerBegan = { [weak self] urls, point in
            self?.wheel.show(near: point, urls: urls)
        }
        dragMonitor.onDragMoved = { [weak self] point in
            self?.wheel.updateCursor(point)
        }
        dragMonitor.onTriggerEnded = { [weak self] in
            self?.wheel.hide()
        }
        dragMonitor.onKey = { [weak self] key in
            self?.wheel.handle(key)
        }
        dragMonitor.onScroll = { [weak self] steps in
            self?.wheel.scroll(steps: steps)
        }
        dragMonitor.start()
    }

    /// When the permissions flip to granted while the app is running, restart the
    /// monitor and offer a one-click restart (macOS often needs it).
    private func watchForPermissionChanges() {
        guard !PermissionManager.allGranted else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard PermissionManager.allGranted else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            AppLog.write("permissions granted while running")
            self?.dragMonitor.start()
            PermissionManager.promptRestart()
        }
    }

    // MARK: - Conversion

    private func run(_ item: WheelItem, _ urls: [URL]) {
        AppLog.write("run start: \(item.id) on \(urls.count) file(s)")
        if item.opensOwnWindow {
            hud.hide()      // the crop window or trim dialog is the feedback
        } else {
            hud.showWorking(title: ItemRunner.workingTitle(for: item, count: urls.count))
        }
        ItemRunner.run(item, urls: urls) { [weak self] summary in
            self?.finishConversion(summary, title: item.label)
        }
    }

    private func showDetail(_ text: String, title: String) {
        hud.hide()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy")
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func finishConversion(_ summary: ConversionSummary, title: String) {
        if summary.undoable { HistoryStore.shared.record(title: title, outputs: summary.outputs) }
        if let detail = summary.detail {
            showDetail(detail, title: summary.message ?? "Details")
            return
        }
        AppLog.write("convert done: \(summary.outputs.count) ok, \(summary.failures.count) failed")
        if summary.failures.isEmpty {
            if AppSettings.playSound { NSSound(named: "Glass")?.play() }
            hud.showDone(outputs: summary.outputs, message: summary.message ?? "Done")
        } else {
            hud.hide()
            showFailures(summary)
        }
    }

    private func showFailures(_ summary: ConversionSummary) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        let n = summary.failures.count
        alert.messageText = "Couldn’t convert \(n) file\(n == 1 ? "" : "s")"

        var lines = summary.failures.prefix(5).map { "• \($0.name): \($0.message)" }
        if n > 5 { lines.append("…and \(n - 5) more") }
        if !summary.outputs.isEmpty { lines.append("\n\(summary.outputs.count) converted fine.") }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        if !summary.outputs.isEmpty { alert.addButton(withTitle: "Reveal in Finder") }
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting(summary.outputs)
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Convrt")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Convrt")
        }

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        let dropZoneItem = NSMenuItem(title: "Drop Zone…", action: #selector(openDropZone), keyEquivalent: "")
        dropZoneItem.target = self
        menu.addItem(dropZoneItem)

        let shelfItem = NSMenuItem(title: "Show or Hide Shelf", action: #selector(toggleShelf), keyEquivalent: "")
        shelfItem.target = self
        menu.addItem(shelfItem)

        recentItem = NSMenuItem(title: "Recent Conversions", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        menu.addItem(recentItem)

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Check Permissions…", action: #selector(checkPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let resetItem = NSMenuItem(title: "Reset Permissions…", action: #selector(resetPermissions), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        let diagnosticsItem = NSMenuItem(title: "Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        let aboutItem = NSMenuItem(title: "About Convrt", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Convrt", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        rebuildRecentMenu()
    }

    // MARK: - Watch folders

    private func startWatchFolders() {
        watcher.apply(rules: WatchRuleStore.load())
        watcher.start()
        NotificationCenter.default.addObserver(forName: .watchRulesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.watcher.apply(rules: WatchRuleStore.load())
        }
    }

    private func watchFinished(_ summary: ConversionSummary, _ rule: WatchRule) {
        if !summary.failures.isEmpty { AppLog.write("watch folder: \(summary.failures.count) file(s) failed") }
        guard !summary.outputs.isEmpty else { return }
        HistoryStore.shared.record(title: "Watch · \(rule.format.uppercased())", outputs: summary.outputs)
        let n = summary.outputs.count
        hud.showDone(outputs: summary.outputs, message: "Watch folder: made \(n) file\(n == 1 ? "" : "s")")
    }

    // MARK: - Recent conversions

    private func rebuildRecentMenu() {
        guard let sub = recentItem?.submenu else { return }
        sub.removeAllItems()
        let entries = HistoryStore.shared.entries
        guard !entries.isEmpty else {
            let none = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
            return
        }
        let when = RelativeDateTimeFormatter()
        when.unitsStyle = .short
        for entry in entries {
            let n = entry.outputs.count
            let title = "\(entry.title) · \(n) file\(n == 1 ? "" : "s") · \(when.localizedString(for: entry.date, relativeTo: Date()))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let inner = NSMenu()
            let reveal = NSMenuItem(title: "Show in Finder", action: #selector(revealRecent(_:)), keyEquivalent: "")
            reveal.target = self
            reveal.representedObject = entry.id
            let undo = NSMenuItem(title: "Undo (Move to Trash)", action: #selector(undoRecent(_:)), keyEquivalent: "")
            undo.target = self
            undo.representedObject = entry.id
            inner.addItem(reveal)
            inner.addItem(undo)
            item.submenu = inner
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        sub.addItem(clear)
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let entry = HistoryStore.shared.entries.first(where: { $0.id == id }) else { return }
        let existing = entry.outputs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty { hud.showDone(outputs: [], message: "Those files are gone") }
        else { NSWorkspace.shared.activateFileViewerSelecting(existing) }
    }

    @objc private func undoRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        let r = HistoryStore.shared.undo(id)
        var parts: [String] = []
        if r.trashed > 0 { parts.append("Moved \(r.trashed) file\(r.trashed == 1 ? "" : "s") to the Trash") }
        if r.missing > 0 { parts.append("\(r.missing) already gone") }
        if r.failed > 0 { parts.append("\(r.failed) couldn’t be moved") }
        hud.showDone(outputs: [], message: parts.isEmpty ? "Nothing to undo" : parts.joined(separator: ", "))
    }

    @objc private func clearHistory() { HistoryStore.shared.clear() }

    // MARK: - Actions

    @objc private func openSettings() { settingsController.show() }

    @objc private func openDropZone() { dropZone.show() }

    @objc private func toggleShelf() { ShelfController.shared.toggle() }

    @objc private func checkPermissions() { PermissionManager.check(showWhenGranted: true) }

    @objc private func resetPermissions() { PermissionManager.resetGrants() }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showDiagnostics() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Convrt Diagnostics"
        alert.informativeText = Diagnostics.report(monitor: dragMonitor)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show Log in Finder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([AppLog.url])
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
