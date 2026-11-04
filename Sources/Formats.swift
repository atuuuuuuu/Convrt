import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FileKind { case image, pdf, audio, video, other }

enum OutputFormat: String {
    case png, jpg, heic, tiff, bmp, gif, webp, avif, pdf

    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    var utType: UTType? {
        switch self {
        case .png:  return .png
        case .jpg:  return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .bmp:  return .bmp
        case .gif:  return .gif
        case .webp: return .webP
        case .avif: return UTType("public.avif")
        case .pdf:  return .pdf
        }
    }

    var isLossy: Bool { self == .jpg || self == .heic || self == .webp || self == .avif }
    /// JPG and BMP can't hold transparency, so transparent pixels are filled white.
    var supportsAlpha: Bool { !(self == .jpg || self == .bmp) }

    /// True when ImageIO on this Mac can write the format. Formats that macOS
    /// can't encode (often WEBP and AVIF) simply don't appear on the wheel.
    var canEncode: Bool {
        if self == .pdf { return true }
        guard let id = utType?.identifier else { return false }
        let ids = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return ids.contains(id)
    }
}

enum FormatCatalog {
    static func kind(of url: URL) -> FileKind {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return .other      // folders and .app bundles
        }
        guard let t = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .other }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .svg) { return .other }
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
        return .other
    }

    static func formats(for kind: FileKind) -> [OutputFormat] {
        switch kind {
        case .image: return [.png, .jpg, .heic, .tiff, .bmp, .gif, .pdf, .webp, .avif].filter { $0.canEncode }
        case .pdf:   return [.png, .jpg, .heic, .tiff].filter { $0.canEncode }
        default:     return []     // audio and video arrive with the ffmpeg stage
        }
    }

    /// Formats valid for every dragged file (empty means "can't convert").
    static func formats(for urls: [URL]) -> [OutputFormat] {
        guard !urls.isEmpty else { return [] }
        var result: [OutputFormat]? = nil
        for url in urls {
            let f = formats(for: kind(of: url))
            result = result.map { r in r.filter { f.contains($0) } } ?? f
        }
        var list = result ?? []

        // If every file already is one format, don't offer converting to itself.
        let exts = Set(urls.map { normalizedExtension($0) })
        if exts.count == 1, let only = exts.first {
            list.removeAll { $0.fileExtension == only }
        }
        return Array(list.prefix(8))
    }

    private static func normalizedExtension(_ url: URL) -> String {
        let e = url.pathExtension.lowercased()
        switch e {
        case "jpeg", "jpe": return "jpg"
        case "tif": return "tiff"
        case "heif": return "heic"
        default: return e
        }
    }
}
