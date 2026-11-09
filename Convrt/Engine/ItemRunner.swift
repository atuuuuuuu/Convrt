import Foundation

/// Runs whatever slice the user picked, off the main thread, and reports one summary.
enum ItemRunner {
    /// "Converting 3 files to PNG…", "Compressing 2 files…"
    static func workingTitle(for item: WheelItem, count: Int) -> String {
        let files = "\(count) file\(count == 1 ? "" : "s")"
        switch item.action {
        case .convert(let format): return "Converting \(files) to \(format.label)…"
        case .tool:                return "\(item.label): \(files)…"
        case .action:              return "\(item.label)…"
        }
    }

    static func run(_ item: WheelItem, urls: [URL], completion: @escaping (ConversionSummary) -> Void) {
        // Crop has its own window and walks through the images one by one.
        if case .tool(.crop) = item.action {
            DispatchQueue.main.async { CropWindowController.shared.run(urls: urls, completion: completion) }
            return
        }
        // Trim asks for a start and end first.
        if case .tool(.trim) = item.action {
            DispatchQueue.main.async {
                guard let range = TrimPrompt.ask(duration: VideoTools.duration(of: urls[0])) else {
                    var cancelled = ConversionSummary(); cancelled.message = "Trim cancelled"
                    completion(cancelled)
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let summary = ToolEngine.trim(urls: urls, start: range.start, end: range.end)
                    DispatchQueue.main.async { completion(summary) }
                }
            }
            return
        }
        // Actions talk to AppKit (share sheet, open panel), so they run on the main thread.
        if case .action(let id) = item.action {
            DispatchQueue.main.async { ActionRunner.run(id, urls: urls, completion: completion) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let summary: ConversionSummary
            switch item.action {
            case .convert(let format):
                summary = Converter.convert(urls: urls, to: format)
            case .tool(let id):
                summary = ToolEngine.run(id, urls: urls)
            case .action:
                summary = ConversionSummary(outputs: [],
                                            failures: [ConversionFailure(name: item.label, message: "Not available yet.")])
            }
            DispatchQueue.main.async { completion(summary) }
        }
    }
}
