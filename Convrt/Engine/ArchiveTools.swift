import Foundation

/// ZIP and unzip with the tools that ship with macOS. Nothing is overwritten or merged.
enum ArchiveTools {
    private static func run(_ tool: String, _ args: [String], in cwd: URL? = nil) throws -> (status: Int32, errors: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.currentDirectoryURL = cwd
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// One item makes "<name>.zip"; several items from one folder make "<folder name>.zip".
    static func zip(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw ToolError("Nothing to zip.") }
        let parent = first.deletingLastPathComponent().standardizedFileURL
        guard urls.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == parent }) else {
            throw ToolError("To zip several items together, they need to be in the same folder.")
        }
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
        let base = urls.count > 1 ? parent.lastPathComponent
            : (isDir.boolValue ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent)

        let dir = AppSettings.outputDirectory(for: first)
        guard FileManager.default.isWritableFile(atPath: dir.path) else {
            throw ToolError("No permission to save in “\(dir.lastPathComponent)”.")
        }
        let out = OutputNaming.uniqueURL(dir: dir, base: base, ext: "zip")
        let result: (status: Int32, errors: String)
        do { result = try run("/usr/bin/zip", ["-r", "-q", "-y", "-X", out.path, "--"] + urls.map(\.lastPathComponent), in: parent) }
        catch { throw ToolError("Couldn’t start the zip tool: \(error.localizedDescription)") }
        guard result.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            try? FileManager.default.removeItem(at: out)
            throw ToolError("Couldn’t create the zip." + (result.errors.isEmpty ? "" : " \(result.errors)"))
        }
        return out
    }

    /// Extracts next to the archive. A lone top-level folder or file is not wrapped in another folder.
    /// Entries that try to escape with "../" are neutralised by `unzip` and land inside the new folder.
    static func unzip(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let dir = AppSettings.outputDirectory(for: url)
        guard fm.isWritableFile(atPath: dir.path) else { throw ToolError("No permission to save in “\(dir.lastPathComponent)”.") }

        let temp = dir.appendingPathComponent(".convrt-unzip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: false)
        var keepTemp = false
        defer { if !keepTemp { try? fm.removeItem(at: temp) } }

        let result: (status: Int32, errors: String)
        do { result = try run("/usr/bin/unzip", ["-q", url.path, "-x", "__MACOSX/*", "-d", temp.path]) }
        catch { throw ToolError("Couldn’t start the unzip tool: \(error.localizedDescription)") }
        // 0 = fine, 1 = finished with warnings (for example a skipped "../" entry); anything else is a failure.
        guard result.status == 0 || result.status == 1 else {
            throw ToolError("Couldn’t open this archive. It may be damaged or not a zip file.")
        }

        let items = ((try? fm.contentsOfDirectory(atPath: temp.path)) ?? []).filter { $0 != ".DS_Store" }
        guard !items.isEmpty else { throw ToolError("This archive is empty.") }

        if items.count == 1, let only = items.first {
            let source = temp.appendingPathComponent(only)
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: source.path, isDirectory: &isDir)
            let target = isDir.boolValue
                ? OutputNaming.uniqueURL(dir: dir, base: only, ext: "")
                : OutputNaming.uniqueURL(dir: dir, base: (only as NSString).deletingPathExtension, ext: (only as NSString).pathExtension)
            try fm.moveItem(at: source, to: target)
            return target
        }
        let target = OutputNaming.uniqueURL(dir: dir, base: url.deletingPathExtension().lastPathComponent, ext: "")
        try fm.moveItem(at: temp, to: target)
        keepTemp = true
        return target
    }
}
