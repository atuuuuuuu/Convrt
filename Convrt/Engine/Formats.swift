import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FileKind { case image, pdf, audio, video, other }

enum OutputFormat: String, CaseIterable {
    case png, jpg, heic, tiff, bmp, gif, webp, avif, pdf
    case wav, aiff, m4a, flac, mp3        // audio
    case mp4, mov                          // video

    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    /// What kind of file this format produces.
    var category: FileKind {
        switch self {
        case .pdf: return .pdf
        case .wav, .aiff, .m4a, .flac, .mp3: return .audio
        case .mp4, .mov: return .video
        default: return .image
        }
    }

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
        case .wav:  return .wav
        case .aiff: return .aiff
        case .m4a:  return UTType("public.mpeg-4-audio")
        case .flac: return UTType("org.xiph.flac")
        case .mp3:  return .mp3
        case .mp4:  return .mpeg4Movie
        case .mov:  return .quickTimeMovie
        }
    }

    var isLossy: Bool { self == .jpg || self == .heic || self == .webp || self == .avif }
    /// JPG and BMP can't hold transparency, so transparent pixels are filled white.
    var supportsAlpha: Bool { !(self == .jpg || self == .bmp) }

    /// True when ImageIO on this Mac can write the format. Formats that macOS
    /// can't encode (often WEBP and AVIF) simply don't appear on the wheel.
    var canEncode: Bool {
        switch category {
        case .audio: return self == .mp3 ? MP3Encoder.isAvailable : true    // macOS can't write MP3 by itself
        case .video: return true
        default: break
        }
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
        case .audio: return [.wav, .mp3, .m4a, .flac, .aiff].filter { $0.canEncode }
        case .video: return [.mp4, .mov, .m4a, .wav, .mp3].filter { $0.canEncode }
        default:     return []
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
        return Array(list.prefix(12))
    }

    private static func normalizedExtension(_ url: URL) -> String {
        let e = url.pathExtension.lowercased()
        switch e {
        case "jpeg", "jpe": return "jpg"
        case "tif": return "tiff"
        case "heif": return "heic"
        case "aif": return "aiff"
        case "m4v": return "mp4"
        default: return e
        }
    }
}
