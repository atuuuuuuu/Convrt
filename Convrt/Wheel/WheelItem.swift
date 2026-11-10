import Foundation

/// The three wheels. Option cycles through them in this order.
enum WheelKind: Int, CaseIterable {
    case convert, tools, actions

    var title: String {
        switch self {
        case .convert: return "Convert"
        case .tools:   return "Tools"
        case .actions: return "Actions"
        }
    }
}

enum ToolID: String, Equatable {
    case compress, resize, stripMetadata, rotateLeft, rotateRight, flipHorizontal
    case crop, cropSquare, mergePDF, removeBackground, info
    case mute, trim, snapshot, extractAudio
    case splitPDF, extractText, zip, unzip
}

enum ActionID: String, Equatable {
    case airDrop, floatShelf, copyPath, revealInFinder, openInTerminal, copyTo, moveTo, quickLook
}

enum ItemAction: Equatable {
    case convert(OutputFormat)
    case tool(ToolID)
    case action(ActionID)
}

/// One slice of a wheel. Pure data: what runs it lives in `ItemRunner`.
struct WheelItem: Identifiable, Equatable {
    let id: String
    let label: String      // keep short: it has to fit inside a wedge
    let symbol: String     // SF Symbol name
    let action: ItemAction

    /// These open their own window or dialog, so the "working" card would only get in the way.
    var opensOwnWindow: Bool { action == .tool(.crop) || action == .tool(.trim) }
}

enum WheelCatalog {
    static let maxItems = 12

    static func items(for kind: WheelKind, urls: [URL]) -> [WheelItem] {
        guard !urls.isEmpty else { return [] }
        let list: [WheelItem]
        switch kind {
        case .convert: list = convertItems(urls)
        case .tools:   list = toolItems(urls)
        case .actions: list = actionItems()
        }
        return Array(list.prefix(maxItems))
    }

    // MARK: - Convert

    private static func convertItems(_ urls: [URL]) -> [WheelItem] {
        FormatCatalog.formats(for: urls).map {
            WheelItem(id: "convert.\($0.rawValue)", label: $0.label,
                      symbol: "arrow.triangle.2.circlepath", action: .convert($0))
        }
    }

    // MARK: - Tools

    private static func toolItems(_ urls: [URL]) -> [WheelItem] {
        func tool(_ id: ToolID, _ label: String, _ symbol: String) -> WheelItem {
            WheelItem(id: "tool.\(id.rawValue)", label: label, symbol: symbol, action: .tool(id))
        }
        let info = tool(.info, "Info", "info.circle")
        if urls.allSatisfy({ FormatCatalog.kind(of: $0) == .video }) {
            return [tool(.mute, "Mute", "speaker.slash"),
                    tool(.trim, "Trim…", "scissors"),
                    tool(.snapshot, "Snapshot", "camera"),
                    tool(.extractAudio, "Extract Audio", "waveform"),
                    info]
        }
        let allImages = urls.allSatisfy { FormatCatalog.kind(of: $0) == .image }
        if allImages {
            var items = [
                tool(.compress, "Compress", "arrow.down.right.and.arrow.up.left"),
                tool(.resize, "Resize", "arrow.up.left.and.arrow.down.right"),
                tool(.stripMetadata, "Strip Data", "eraser"),
                tool(.rotateLeft, "Turn Left", "rotate.left"),
                tool(.rotateRight, "Turn Right", "rotate.right"),
                tool(.flipHorizontal, "Flip", "arrow.left.and.right.righttriangle.left.righttriangle.right"),
                tool(.crop, "Crop…", "crop"),
                tool(.cropSquare, "Crop 1:1", "square.dashed"),
                tool(.removeBackground, "Cut Out", "person.crop.circle.badge.minus")
            ]
            if urls.count >= 2 { items.append(tool(.mergePDF, "Merge PDF", "doc.on.doc")) }
            items.append(info)
            return items
        }

        let zip = tool(.zip, "Zip", "doc.zipper")
        if urls.allSatisfy({ FormatCatalog.kind(of: $0) == .pdf }) {
            var items: [WheelItem] = []
            if urls.count >= 2 { items.append(tool(.mergePDF, "Merge PDFs", "doc.on.doc")) }
            items += [tool(.splitPDF, "Split Pages", "square.split.2x1"),
                      tool(.extractText, "Get Text", "text.alignleft"),
                      zip, info]
            return items
        }

        var items = [zip]
        if urls.allSatisfy({ $0.pathExtension.lowercased() == "zip" }) {
            items.insert(tool(.unzip, "Unzip", "archivebox"), at: 0)
        }
        items.append(info)
        return items
    }

    // MARK: - Actions

    private static func actionItems() -> [WheelItem] {
        func action(_ id: ActionID, _ label: String, _ symbol: String) -> WheelItem {
            WheelItem(id: "action.\(id.rawValue)", label: label, symbol: symbol, action: .action(id))
        }
        return [
            action(.airDrop, "AirDrop", "dot.radiowaves.left.and.right"),
            action(.floatShelf, "Float", "tray.full"),
            action(.copyPath, "Copy Path", "doc.on.clipboard"),
            action(.revealInFinder, "Reveal", "folder"),
            action(.openInTerminal, "Terminal", "terminal"),
            action(.copyTo, "Copy To…", "doc.on.doc"),
            action(.moveTo, "Move To…", "arrow.right.doc.on.clipboard"),
            action(.quickLook, "Quick Look", "eye")
        ]
    }
}
