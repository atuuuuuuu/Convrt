import Foundation

enum ShellQuote {
    /// Wraps text in single quotes for a POSIX shell; an embedded ' becomes '\'' .
    static func single(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
