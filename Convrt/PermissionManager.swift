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
}
