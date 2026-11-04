import AppKit

/// Plain-text health report for "it works in Xcode but not on its own".
enum Diagnostics {
    static func report(monitor: DragMonitor) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        var lines: [String] = []
        lines.append("Version \(version) (\(build))")
        lines.append("Location: \(Bundle.main.bundlePath)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Accessibility: \(PermissionManager.accessibilityGranted ? "granted" : "NOT granted")")
        lines.append("Input Monitoring: \(PermissionManager.inputMonitoringGranted ? "granted" : "NOT granted")")
        lines.append("Drag monitor running: \(monitor.isRunning ? "yes" : "no")")
        lines.append("Events seen: \(monitor.eventsSeen)")
        lines.append("File drags detected: \(monitor.dragsDetected)")
        lines.append("Signing: \(signatureSummary(path: Bundle.main.bundlePath))")
        return lines.joined(separator: "\n")
    }

    private static func signatureSummary(path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=2", path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        do { try process.run() } catch { return "unknown" }
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if text.contains("not signed at all") { return "NOT signed" }
        let hardened = text.contains("(runtime)") ? "hardened runtime on" : "hardened runtime off"
        if text.contains("Signature=adhoc") {
            return "ad-hoc, \(hardened). Permissions reset on every rebuild; choose a Team in Signing & Capabilities"
        }
        if let line = text.split(separator: "\n").first(where: { $0.hasPrefix("Authority=") }) {
            return "\(line.dropFirst("Authority=".count)), \(hardened)"
        }
        return "signed, \(hardened)"
    }
}
