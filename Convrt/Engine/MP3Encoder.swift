import Foundation

/// macOS can read MP3 but cannot write it, so MP3 output needs `lame` (preferred) or `ffmpeg`.
/// Both are found in the usual Homebrew/MacPorts folders because a menu bar app has almost no PATH.
enum MP3Encoder {
    enum Engine: Equatable {
        case lame(URL)
        case ffmpeg(URL)
    }

    static var defaultSearchDirs: [URL] {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin",
                    NSHomeDirectory() + "/.local/bin"]
        dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func findEngine(searchDirs: [URL] = defaultSearchDirs) -> Engine? {
        let fm = FileManager.default
        for name in ["lame", "ffmpeg"] {
            for dir in searchDirs {
                let candidate = dir.appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate.path) {
                    return name == "lame" ? .lame(candidate) : .ffmpeg(candidate)
                }
            }
        }
        return nil
    }

    static var isAvailable: Bool { findEngine() != nil }

    static let installHint = "MP3 needs the lame encoder. Install it with: brew install lame"

    /// Encodes a WAV file to MP3 at about 190 kbit/s (VBR quality 2).
    static func encode(wav: URL, to out: URL, engine: Engine) throws {
        let process = Process()
        switch engine {
        case .lame(let exe):
            process.executableURL = exe
            process.arguments = ["--silent", "-V", "2", wav.path, out.path]
        case .ffmpeg(let exe):
            process.executableURL = exe
            process.arguments = ["-y", "-loglevel", "error", "-i", wav.path, "-codec:a", "libmp3lame", "-q:a", "2", out.path]
        }
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) else {
            try? FileManager.default.removeItem(at: out)
            let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AudioError("The MP3 encoder failed." + (detail.isEmpty ? "" : " \(detail)"))
        }
    }
}

struct AudioError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
