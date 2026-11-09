import AppKit
import ApplicationServices

enum PermissionManager {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
    static var allGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    /// Registers the app in the Privacy lists (and triggers the system prompts).
    /// An app only appears in those lists after it has asked once.
    private static func requestAccess() {
        if !accessibilityGranted {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        if !inputMonitoringGranted {
            _ = CGRequestListenEventAccess()
        }
    }

    private static func openPane(_ anchor: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows a guide if something is missing. Pass `showWhenGranted: true`
    /// when the user asks for it from the menu or Settings.
    static func check(showWhenGranted: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()

        if allGranted {
            guard showWhenGranted else { return }
            alert.messageText = "All permissions granted"
            alert.informativeText = "Accessibility and Input Monitoring are both enabled."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        var missing: [String] = []
        if !accessibilityGranted { missing.append("• Accessibility") }
        if !inputMonitoringGranted { missing.append("• Input Monitoring") }

        alert.alertStyle = .warning
        alert.messageText = "Convrt needs permission"
        alert.informativeText = """
        To notice when you hold a key while dragging files, Convrt needs:

        \(missing.joined(separator: "\n"))

        Click "Open System Settings" and switch Convrt on in each list. \
        If Convrt is already listed but still doesn't work, select it, click the − button, and add it again.

        Everything stays on your Mac.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            requestAccess()
            openPane(accessibilityGranted ? "Privacy_ListenEvent" : "Privacy_Accessibility")
        }
    }

    /// New permissions often only take effect after a restart.
    static func promptRestart() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Permissions enabled"
        alert.informativeText = "Convrt needs to restart once to start using them."
        alert.addButton(withTitle: "Restart Convrt")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { relaunch() }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "sleep 0.8; /usr/bin/open \"\(path)\""]
        try? helper.run()
        NSApp.terminate(nil)
    }

    // MARK: - Reset

    /// The commands that clear Convrt's Accessibility and Input Monitoring entries,
    /// so stale entries from older builds can't block a fresh grant.
    static func resetCommands(bundleID: String) -> [[String]] {
        [["tccutil", "reset", "Accessibility", bundleID],
         ["tccutil", "reset", "ListenEvent", bundleID]]
    }

    /// Asks first, clears both entries, then restarts so macOS asks again from scratch.
    static func resetGrants() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Reset Convrt’s permissions?"
        alert.informativeText = "Convrt will forget its Accessibility and Input Monitoring entries, restart, and ask again. Use this once after changing how Convrt is signed."
        alert.addButton(withTitle: "Reset and Restart")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for command in resetCommands(bundleID: id) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/\(command[0])")
            process.arguments = Array(command.dropFirst())
            try? process.run()
            process.waitUntilExit()
        }
        AppLog.write("permissions reset for \(id)")
        relaunch()
    }
}
