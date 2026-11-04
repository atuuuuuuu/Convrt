import AppKit

enum TriggerKey: String, CaseIterable, Identifiable {
    case shift, option, control, command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shift:   return "Shift ⇧"
        case .option:  return "Option ⌥"
        case .control: return "Control ⌃"
        case .command: return "Command ⌘"
        }
    }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift:   return .shift
        case .option:  return .option
        case .control: return .control
        case .command: return .command
        }
    }
}

enum OutputMode: String {
    case sameFolder, customFolder
}

/// One place for every user setting. The Settings window writes these keys
/// with @AppStorage, and the rest of the app reads them here.
enum AppSettings {
    enum Key {
        static let imageQuality = "imageQuality"
        static let outputMode = "outputMode"
        static let customOutputPath = "customOutputPath"
        static let deleteOriginal = "deleteOriginal"
        static let convertTrigger = "convertTrigger"
        static let playSound = "playSound"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.imageQuality: 0.85,
            Key.outputMode: OutputMode.sameFolder.rawValue,
            Key.customOutputPath: "",
            Key.deleteOriginal: false,
            Key.convertTrigger: TriggerKey.shift.rawValue,
            Key.playSound: true
        ])
    }

    static var imageQuality: Double { UserDefaults.standard.double(forKey: Key.imageQuality) }
    static var deleteOriginal: Bool { UserDefaults.standard.bool(forKey: Key.deleteOriginal) }
    static var playSound: Bool { UserDefaults.standard.bool(forKey: Key.playSound) }

    static var convertTrigger: TriggerKey {
        TriggerKey(rawValue: UserDefaults.standard.string(forKey: Key.convertTrigger) ?? "") ?? .shift
    }

    /// Folder where the result for `source` is saved.
    /// Falls back to the original's folder if the chosen folder is missing or not writable.
    static func outputDirectory(for source: URL) -> URL {
        let sameFolder = source.deletingLastPathComponent()
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Key.outputMode) == OutputMode.customFolder.rawValue,
              let path = defaults.string(forKey: Key.customOutputPath), !path.isEmpty else {
            return sameFolder
        }
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue, fm.isWritableFile(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return sameFolder
    }
}
