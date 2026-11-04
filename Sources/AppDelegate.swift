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

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()

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
        wheel.onConvert = { [weak self] format, urls in
            self?.runConversion(format, urls)
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

    private func runConversion(_ format: OutputFormat, _ urls: [URL]) {
        AppLog.write("convert start: \(urls.count) file(s) -> \(format.label)")
        hud.showWorking(count: urls.count, format: format)
        DispatchQueue.global(qos: .userInitiated).async {
            let summary = Converter.convert(urls: urls, to: format)
            DispatchQueue.main.async { [weak self] in
                self?.finishConversion(summary)
            }
        }
    }

    private func finishConversion(_ summary: ConversionSummary) {
        AppLog.write("convert done: \(summary.outputs.count) ok, \(summary.failures.count) failed")
        if summary.failures.isEmpty {
            if AppSettings.playSound { NSSound(named: "Glass")?.play() }
            hud.showDone(outputs: summary.outputs)
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

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Check Permissions…", action: #selector(checkPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

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
    }

    // MARK: - Actions

    @objc private func openSettings() { settingsController.show() }

    @objc private func checkPermissions() { PermissionManager.check(showWhenGranted: true) }

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
