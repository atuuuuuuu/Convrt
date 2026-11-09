import Foundation

/// Where the CLI prints. Tests replace these to capture output.
enum CLIIO {
    static var out: (String) -> Void = { print($0) }
    static var err: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    static func reset() {
        out = { print($0) }
        err = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    }
}

let cliVersion = "1.0"

let cliUsage = """
convrt \(cliVersion): convert files from Terminal, the same way the Convrt app does. Everything stays on your Mac.

USAGE
  convrt convert <files...> --to <format> [--out <folder>]
  convrt tool <name> <files...> [--out <folder>]
  convrt tool trim <video> --from <time> --to <time>
  convrt formats [file]
  convrt watch <folder> --to <format>

EXAMPLES
  convrt convert photo.heic --to jpg
  convrt convert song.wav --to mp3 --out ~/Music
  convrt tool compress *.jpg
  convrt tool zip Photos
  convrt formats song.mp3
  convrt watch ~/Downloads/Incoming --to pdf

Results are saved next to the original (or in --out) and never overwrite anything.
Originals are never deleted. Exit status: 0 done, 1 some files failed, 2 bad command.
"""

/// The whole command-line program. Returns the exit status.
public func runCLI(_ args: [String]) -> Int32 {
    AppSettings.registerDefaults()
    do {
        return try execute(try CLIParser.parse(args))
    } catch {
        CLIIO.err("convrt: \(error.localizedDescription)")
        CLIIO.err("Run “convrt --help” for usage.")
        return 2
    }
}

private func urls(_ paths: [String]) -> [URL] {
    paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
}

/// Points results at --out (in memory only, never saved to preferences).
private func useOutputFolder(_ folder: String?) throws {
    guard let folder else { return }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
        throw CLIError("The output folder “\(folder)” doesn’t exist.")
    }
    UserDefaults.standard.register(defaults: [AppSettings.Key.outputMode: OutputMode.customFolder.rawValue,
                                              AppSettings.Key.customOutputPath: folder])
}

/// Prints a summary and returns the exit status for it.
private func report(_ summary: ConversionSummary) -> Int32 {
    for o in summary.outputs { CLIIO.out(o.path) }
    if let detail = summary.detail { CLIIO.out(detail) }
    for f in summary.failures { CLIIO.err("convrt: \(f.name): \(f.message)") }
    return summary.failures.isEmpty ? 0 : 1
}

private func execute(_ command: Command) throws -> Int32 {
    switch command {
    case .help:
        CLIIO.out(cliUsage)
        return 0
    case .version:
        CLIIO.out("convrt \(cliVersion)")
        return 0

    case .formats(let file):
        if let file {
            let list = FormatCatalog.formats(for: urls([file]))
            CLIIO.out(list.isEmpty ? "No conversions for this file type." : list.map(\.rawValue).joined(separator: " "))
        } else {
            for (title, kind) in [("images", FileKind.image), ("pdf", .pdf), ("audio", .audio), ("video", .video)] {
                let names = OutputFormat.allCases.filter { $0.category == kind && $0.canEncode }.map(\.rawValue)
                CLIIO.out("\(title): \(names.joined(separator: " "))")
            }
            if !MP3Encoder.isAvailable { CLIIO.out("(mp3 output is off: \(MP3Encoder.installHint))") }
        }
        return 0

    case .convert(let files, let format, let folder):
        try useOutputFolder(folder)
        return convertEach(urls(files), format)

    case .tool(let id, let files, let folder):
        try useOutputFolder(folder)
        let list = urls(files)
        let missing = list.filter { !FileManager.default.fileExists(atPath: $0.path) }
        for m in missing { CLIIO.err("convrt: \(m.path): no such file") }
        let existing = list.filter { !missing.contains($0) }
        guard !existing.isEmpty else { return 1 }
        let code = report(ToolEngine.run(id, urls: existing))
        return missing.isEmpty ? code : 1

    case .trim(let files, let start, let end, let folder):
        try useOutputFolder(folder)
        return report(ToolEngine.trim(urls: urls(files), start: start, end: end))

    case .watch(let folder, let format):
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
            throw CLIError("The folder “\(folder)” doesn’t exist.")
        }
        let service = WatchFolderService(onResult: { summary, _ in _ = report(summary) })
        service.apply(rules: [WatchRule(folder: folder, format: format.rawValue, enabled: true)])
        service.start()
        CLIIO.out("Watching \(folder) → \(format.rawValue). Press Control-C to stop.")
        RunLoop.main.run()
        return 0
    }
}

/// Files are converted one at a time so one bad file never stops the rest. Originals are never trashed.
private func convertEach(_ files: [URL], _ format: OutputFormat) -> Int32 {
    var failed = false
    for url in files {
        guard FileManager.default.fileExists(atPath: url.path) else {
            CLIIO.err("convrt: \(url.path): no such file")
            failed = true
            continue
        }
        if report(Converter.convert(urls: [url], to: format, keepOriginals: true)) != 0 { failed = true }
    }
    return failed ? 1 : 0
}

public func cliMain() -> Never {
    exit(runCLI(Array(CommandLine.arguments.dropFirst())))
}
