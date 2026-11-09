import AppKit

/// A small dialog asking for the start and end of a trim. Main thread only.
enum TrimPrompt {
    /// Returns nil when the user cancels.
    static func ask(duration: Double) -> (start: Double, end: Double)? {
        var message = "Enter times like 1:30 or 12.5 (seconds). The clip is \(TimeParser.format(duration)) long."
        while true {
            let startField = NSTextField(string: "0:00.0")
            let endField = NSTextField(string: TimeParser.format(duration))
            for f in [startField, endField] { f.widthAnchor.constraint(equalToConstant: 120).isActive = true }

            func row(_ title: String, _ field: NSTextField) -> NSStackView {
                let label = NSTextField(labelWithString: title)
                label.widthAnchor.constraint(equalToConstant: 48).isActive = true
                let r = NSStackView(views: [label, field]); r.spacing = 8
                return r
            }
            let stack = NSStackView(views: [row("Start", startField), row("End", endField)])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.frame = NSRect(x: 0, y: 0, width: 190, height: 58)

            let alert = NSAlert()
            alert.messageText = "Trim"
            alert.informativeText = message
            alert.accessoryView = stack
            alert.addButton(withTitle: "Trim")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            alert.window.initialFirstResponder = startField
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            if let s = TimeParser.seconds(from: startField.stringValue),
               let e = TimeParser.seconds(from: endField.stringValue), s < e {
                return (s, e)
            }
            message = "Those times don’t work. The start must come before the end, like 0:05 and 0:20."
        }
    }
}
