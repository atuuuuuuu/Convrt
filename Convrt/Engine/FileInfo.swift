import Foundation
import ImageIO
import PDFKit
import AVFoundation
import UniformTypeIdentifiers

/// The text behind the Info tool: what a file or folder is, in plain words.
enum FileInfo {
    static func describe(_ url: URL) -> String {
        let fm = FileManager.default
        var lines = [url.lastPathComponent]
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return (lines + ["This file no longer exists."]).joined(separator: "\n")
        }

        if isDir.boolValue {
            let c = folderContents(url)
            lines.append("Kind: Folder")
            lines.append("Contains: \(plural(c.files, "file")), \(plural(c.folders, "folder")) (\(bytes(c.size)))")
        } else {
            let type = UTType(filenameExtension: url.pathExtension)
            lines.append("Kind: \(type?.localizedDescription ?? "Document")")
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            lines.append("Size: \(bytes(size))")
            if let type {
                if type.conforms(to: .pdf) { lines += pdfLines(url) }
                else if type.conforms(to: .image) { lines += imageLines(url) }
                else if type.conforms(to: .audio) { lines += audioLines(url) }
                else if type.conforms(to: .movie) || type.conforms(to: .video) { lines += videoLines(url) }
            }
        }
        if let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
            lines.append("Modified: \(modified.formatted(date: .abbreviated, time: .shortened))")
        }
        lines.append("Location: \(url.deletingLastPathComponent().path)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    private static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    private static func folderContents(_ url: URL) -> (files: Int, folders: Int, size: Int) {
        var files = 0, folders = 0, size = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        while let item = e?.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { folders += 1 } else { files += 1; size += values?.fileSize ?? 0 }
        }
        return (files, folders, size)
    }

    private static func imageLines(_ url: URL) -> [String] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return ["Couldn’t read the image details."] }
        var out: [String] = []
        if let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
            out.append("Dimensions: \(w) × \(h) px")
        }
        if let dpi = p[kCGImagePropertyDPIWidth] as? Double, dpi > 0 { out.append("Resolution: \(Int(dpi)) dpi") }
        if let model = p[kCGImagePropertyColorModel] as? String { out.append("Color: \(model)") }
        if let alpha = p[kCGImagePropertyHasAlpha] as? Bool { out.append("Transparency: \(alpha ? "yes" : "no")") }
        if let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let camera = [tiff[kCGImagePropertyTIFFMake], tiff[kCGImagePropertyTIFFModel]].compactMap { $0 as? String }.joined(separator: " ")
            if !camera.isEmpty { out.append("Camera: \(camera)") }
        }
        if let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any], let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            out.append("Taken: \(date)")
        }
        out.append("Location data: \(p[kCGImagePropertyGPSDictionary] != nil ? "yes" : "none")")
        return out
    }

    private static func pdfLines(_ url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return ["Couldn’t read the PDF."] }
        var out = ["Pages: \(doc.pageCount)"]
        if let page = doc.page(at: 0) {
            let r = page.bounds(for: .mediaBox)
            out.append("Page size: \(Int(r.width)) × \(Int(r.height)) pt")
        }
        if let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty { out.append("Title: \(title)") }
        return out
    }

    private static func audioLines(_ url: URL) -> [String] {
        guard let f = try? AVAudioFile(forReading: url) else { return ["Couldn’t read the audio details."] }
        let rate = f.fileFormat.sampleRate
        return ["Duration: \(duration(Double(f.length) / max(rate, 1)))",
                "Sample rate: \(Int(rate)) Hz",
                "Channels: \(f.fileFormat.channelCount == 1 ? "mono" : f.fileFormat.channelCount == 2 ? "stereo" : "\(f.fileFormat.channelCount)")"]
    }

    private static func videoLines(_ url: URL) -> [String] {
        let asset = AVURLAsset(url: url)
        var out = ["Duration: \(duration(asset.duration.seconds))"]
        if let v = asset.tracks(withMediaType: .video).first {
            let s = v.naturalSize.applying(v.preferredTransform)
            out.append("Dimensions: \(Int(abs(s.width))) × \(Int(abs(s.height))) px")
            if v.nominalFrameRate > 0 { out.append("Frame rate: \(String(format: "%.2f", v.nominalFrameRate)) fps") }
        }
        out.append("Audio: \(asset.tracks(withMediaType: .audio).isEmpty ? "none" : "yes")")
        return out
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "unknown" }
        let t = Int(seconds.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}
