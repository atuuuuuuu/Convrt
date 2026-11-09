import Foundation

struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Command: Equatable {
    case help, version
    case formats(file: String?)
    case convert(files: [String], format: OutputFormat, outputFolder: String?)
    case tool(ToolID, files: [String], outputFolder: String?)
    case trim(files: [String], start: Double, end: Double, outputFolder: String?)
    case watch(folder: String, format: OutputFormat)
}

enum CLIParser {
    static let toolNames: [String: ToolID] = [
        "compress": .compress, "resize": .resize, "strip": .stripMetadata, "strip-metadata": .stripMetadata,
        "rotate-left": .rotateLeft, "rotate-right": .rotateRight, "flip": .flipHorizontal,
        "crop-square": .cropSquare, "cutout": .removeBackground, "remove-background": .removeBackground,
        "merge-pdf": .mergePDF, "merge": .mergePDF, "split-pdf": .splitPDF, "split": .splitPDF,
        "text": .extractText, "extract-text": .extractText, "zip": .zip, "unzip": .unzip,
        "mute": .mute, "snapshot": .snapshot, "extract-audio": .extractAudio, "info": .info
    ]

    static let aliases: [String: OutputFormat] = ["jpeg": .jpg, "tif": .tiff, "heif": .heic, "aif": .aiff]

    static func format(named name: String) throws -> OutputFormat {
        let n = name.lowercased()
        if let f = OutputFormat(rawValue: n) ?? aliases[n] { return f }
        throw CLIError("“\(name)” isn’t a format Convrt knows. Choose one of: \(OutputFormat.allCases.map(\.rawValue).joined(separator: ", ")).")
    }

    private struct Options {
        var files: [String] = []
        var to: String?
        var from: String?
        var out: String?
    }

    private static func options(_ args: ArraySlice<String>) throws -> Options {
        var o = Options()
        var i = args.startIndex
        var onlyFiles = false
        func value(_ flag: String, inline: String?) throws -> String {
            if let inline { return inline }
            i += 1
            guard i < args.endIndex else { throw CLIError("\(flag) needs a value.") }
            return args[i]
        }
        while i < args.endIndex {
            let a = args[i]
            if onlyFiles || !a.hasPrefix("-") || a == "-" { o.files.append(a) }
            else if a == "--" { onlyFiles = true }
            else {
                let parts = a.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                let inline = parts.count > 1 ? parts[1] : nil
                switch parts[0] {
                case "--to": o.to = try value("--to", inline: inline)
                case "--from": o.from = try value("--from", inline: inline)
                case "--out": o.out = try value("--out", inline: inline)
                default: throw CLIError("Unknown option “\(parts[0])”.")
                }
            }
            i += 1
        }
        if let out = o.out { o.out = (out as NSString).expandingTildeInPath }
        return o
    }

    static func parse(_ args: [String]) throws -> Command {
        guard let first = args.first else { return .help }
        let rest = args.dropFirst()
        switch first {
        case "--help", "-h", "help": return .help
        case "--version", "-v", "version": return .version

        case "formats":
            return .formats(file: try options(rest).files.first)

        case "convert":
            let o = try options(rest)
            guard !o.files.isEmpty else { throw CLIError("convert needs at least one file.") }
            guard let to = o.to else { throw CLIError("convert needs a target, for example: --to jpg") }
            return .convert(files: o.files, format: try format(named: to), outputFolder: o.out)

        case "tool":
            guard let name = rest.first else { throw CLIError("tool needs a name, for example: convrt tool compress photo.jpg") }
            if name == "crop" { throw CLIError("Crop opens its own window, so it only works in the app. Use “crop-square” for a quick centre crop.") }
            let o = try options(rest.dropFirst())
            guard !o.files.isEmpty else { throw CLIError("\(name) needs at least one file.") }
            if name == "trim" {
                guard let f = o.from, let t = o.to else { throw CLIError("trim needs --from and --to times, like: --from 0:05 --to 0:20") }
                guard let start = TimeParser.seconds(from: f), let end = TimeParser.seconds(from: t), start < end else {
                    throw CLIError("The trim times must look like 12.5 or 1:30, and the start must come before the end.")
                }
                return .trim(files: o.files, start: start, end: end, outputFolder: o.out)
            }
            guard let tool = toolNames[name] else {
                throw CLIError("“\(name)” isn’t a tool. Choose one of: \((toolNames.keys + ["trim"]).sorted().joined(separator: ", ")).")
            }
            return .tool(tool, files: o.files, outputFolder: o.out)

        case "watch":
            let o = try options(rest)
            guard let folder = o.files.first else { throw CLIError("watch needs a folder.") }
            guard let to = o.to else { throw CLIError("watch needs a target, for example: --to pdf") }
            return .watch(folder: (folder as NSString).expandingTildeInPath, format: try format(named: to))

        default:
            throw CLIError("Unknown command “\(first)”.")
        }
    }
}
