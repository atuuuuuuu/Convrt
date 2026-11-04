import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!
    private let settingsController = SettingsWindowController()
    private let dragMonitor = DragMonitor()
    private lazy var wheel = WheelController()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        PermissionManager.check()
        setupDragMonitor()
        watchForPermissionChanges()
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

    /// Monitors started before permission was granted may stay deaf, so once the
    /// permissions flip to granted, restart the monitor.
    private func watchForPermissionChanges() {
        guard !PermissionManager.allGranted else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard PermissionManager.allGranted else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.dragMonitor.start()
            print("Permissions granted, drag monitor restarted")
        }
    }

    // MARK: - Conversion

    private func runConversion(_ format: OutputFormat, _ urls: [URL]) {
        setStatusTitle(" …")
        DispatchQueue.global(qos: .userInitiated).async {
            let summary = Converter.convert(urls: urls, to: format)
            DispatchQueue.main.async { [weak self] in
                self?.finishConversion(summary)
            }
        }
    }

    private func finishConversion(_ summary: ConversionSummary) {
        if summary.failures.isEmpty {
            NSSound(named: "Glass")?.play()
            setStatusTitle(" ✓ \(summary.outputs.count)")
        } else {
            setStatusTitle("")
            showFailures(summary)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.setStatusTitle("")
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
        alert.runModal()
    }

    private func setStatusTitle(_ text: String) {
        statusItem.button?.title = text
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                accessibilityDescription: "Convrt")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
        }

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        let permissionsItem = NSMenuItem(title: "Check Permissions…", action: #selector(checkPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

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
