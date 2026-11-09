import AppKit

/// The Actions wheel: AirDrop, Copy Path, Reveal, Terminal, Copy To, Move To, Quick Look.
/// `run` must be called on the main thread; `completion` is also called on the main thread.
enum ActionRunner {
    private static var airDropService: NSSharingService?   // must outlive the call

    // MARK: - Pure helpers (unit tested)

    /// Paths joined by newlines, unquoted, the way Finder's "Copy as Pathname" does.
    static func copyPathText(for urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    /// Terminal opens in the folder itself, or in the folder that holds a file.
    static func terminalDirectory(for url: URL) -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        return url.deletingLastPathComponent()
    }

    /// Copies or moves every item into `dir`. Never overwrites; one bad item doesn't stop the rest.
    static func transfer(urls: [URL], to dir: URL, move: Bool) -> ConversionSummary {
        var summary = ConversionSummary()
        let fm = FileManager.default
        for url in urls {
            let name = url.lastPathComponent
            guard fm.isWritableFile(atPath: dir.path) else {
                summary.failures.append(ConversionFailure(name: name, message: "No permission to save in “\(dir.lastPathComponent)”."))
                continue
            }
            if move, url.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path {
                summary.failures.append(ConversionFailure(name: name, message: "Already in that folder."))
                continue
            }
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            let target = isDir.boolValue
                ? OutputNaming.uniqueURL(dir: dir, base: name, ext: "")
                : OutputNaming.uniqueURL(dir: dir, base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
            do {
                if move { try fm.moveItem(at: url, to: target) } else { try fm.copyItem(at: url, to: target) }
                summary.outputs.append(target)
            } catch {
                summary.failures.append(ConversionFailure(name: name, message: error.localizedDescription))
            }
        }
        summary.undoable = !move
        return summary
    }

    // MARK: - Running an action

    static func run(_ id: ActionID, urls: [URL], completion: @escaping (ConversionSummary) -> Void) {
        switch id {
        case .airDrop:
            completion(airDrop(urls))
        case .floatShelf:
            ShelfController.shared.add(urls)
            completion(message("Added to the shelf"))
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyPathText(for: urls), forType: .string)
            completion(message(urls.count == 1 ? "Path copied" : "\(urls.count) paths copied"))
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            completion(message("Shown in Finder"))
        case .openInTerminal:
            completion(openTerminal(urls))
        case .copyTo, .moveTo:
            chooseFolderAndTransfer(urls, move: id == .moveTo, completion: completion)
        case .quickLook:
            completion(quickLook(urls))
        }
    }

    private static func message(_ text: String) -> ConversionSummary {
        var s = ConversionSummary()
        s.message = text
        return s
    }

    private static func failure(_ name: String, _ text: String) -> ConversionSummary {
        var s = ConversionSummary()
        s.failures.append(ConversionFailure(name: name, message: text))
        return s
    }

    private static func airDrop(_ urls: [URL]) -> ConversionSummary {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            return failure("AirDrop", "AirDrop isn’t available. Turn on Wi-Fi and Bluetooth, and check AirDrop in Finder.")
        }
        airDropService = service
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        return message("AirDrop: choose a device")
    }

    private static func openTerminal(_ urls: [URL]) -> ConversionSummary {
        guard let first = urls.first else { return failure("Terminal", "Nothing to open.") }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([terminalDirectory(for: first)], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return message("Opened Terminal")
    }

    private static func quickLook(_ urls: [URL]) -> ConversionSummary {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p"] + urls.map(\.path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return failure("Quick Look", error.localizedDescription) }
        return message("Quick Look")
    }

    private static func chooseFolderAndTransfer(_ urls: [URL], move: Bool, completion: @escaping (ConversionSummary) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = move ? "Choose where to move the item(s)" : "Choose where to copy the item(s)"
        panel.prompt = move ? "Move Here" : "Copy Here"
        guard panel.runModal() == .OK, let dir = panel.url else {
            completion(message("Cancelled"))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let summary = transfer(urls: urls, to: dir, move: move)
            DispatchQueue.main.async { completion(summary) }
        }
    }
}
