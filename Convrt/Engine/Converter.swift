import Foundation
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ConversionFailure {
    let name: String
    let message: String
}

struct ConversionSummary {
    var outputs: [URL] = []
    var failures: [ConversionFailure] = []
    /// Shown in the "done" card instead of the default "Done" (actions use this).
    var message: String? = nil
    /// Longer text to show in a dialog (the Info tool uses this).
    var detail: String? = nil
    /// False when the outputs are the user's own files (Move To), which Undo must never trash.
    var undoable = true
}

private struct ConvertError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// All conversion work. Call from a background queue. Fully offline.
enum Converter {
    /// Set by the quality slider in Settings (0.0 to 1.0).
    static var lossyQuality: Double { AppSettings.imageQuality }

    /// `keepOriginals: true` ignores the "move the original to the Trash" setting (automatic runs must never delete files).
    static func convert(urls: [URL], to format: OutputFormat, keepOriginals: Bool = false) -> ConversionSummary {
        var summary = ConversionSummary()
        let quality = lossyQuality
        let trashOriginals = AppSettings.deleteOriginal && !keepOriginals

        // Several images dropped on PDF become one combined PDF.
        if format == .pdf, urls.count > 1, urls.allSatisfy({ FormatCatalog.kind(of: $0) == .image }) {
            do {
                summary.outputs.append(try combineImagesToPDF(urls))
                if trashOriginals {
                    for original in urls { trashOriginal(original, into: &summary) }
                }
            } catch {
                summary.failures.append(ConversionFailure(name: "Combined PDF", message: error.localizedDescription))
            }
            return summary
        }

        for url in urls {
            do {
                summary.outputs.append(contentsOf: try convertOne(url, to: format, quality: quality))
                if trashOriginals { trashOriginal(url, into: &summary) }
            } catch {
                summary.failures.append(ConversionFailure(name: url.lastPathComponent, message: error.localizedDescription))
            }
        }
        return summary
    }

    // MARK: - One file

    private static func convertOne(_ url: URL, to format: OutputFormat, quality: Double) throws -> [URL] {
        let dir = AppSettings.outputDirectory(for: url)
        guard FileManager.default.isWritableFile(atPath: dir.path) else {
            throw ConvertError("No permission to save in “\(dir.lastPathComponent)”.")
        }
        let base = url.deletingPathExtension().lastPathComponent

        switch FormatCatalog.kind(of: url) {
        case .image:
            if format == .pdf { return [try imageToPDF(url, dir: dir, base: base)] }
            return [try imageToImage(url, format: format, dir: dir, base: base, quality: quality)]
        case .pdf:
            return try pdfToImages(url, format: format, dir: dir, base: base, quality: quality)
        case .audio:
            return [try AudioConverter.convert(url, to: format, dir: dir, base: base)]
        case .video:
            return [format.category == .video
                    ? try VideoTools.convert(url, to: format, dir: dir, base: base)
                    : try VideoTools.extractAudio(url, to: format, dir: dir, base: base)]
        default:
            throw ConvertError("This file type isn’t supported yet.")
        }
    }

    // MARK: - Image -> image (ImageIO)

    private static func imageToImage(_ url: URL, format: OutputFormat, dir: URL, base: String, quality: Double) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConvertError("Couldn’t read this image. It may be corrupt.")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let out = uniqueURL(in: dir, base: base, ext: format.fileExtension)
        try write(image, to: out, format: format, quality: quality, properties: props, flatten: false)
        return out
    }

    /// Writes one CGImage with ImageIO. The image keeps its own color profile.
    private static func write(_ image: CGImage, to out: URL, format: OutputFormat, quality: Double,
                              properties: [CFString: Any]?, flatten: Bool) throws {
        guard let type = format.utType else {
            throw ConvertError("\(format.label) isn’t supported on this Mac.")
        }

        var cg = image
        if flatten || (!format.supportsAlpha && hasAlpha(image)) {
            cg = flattenedOnWhite(image) ?? image
        }

        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError("Couldn’t create the \(format.label) file.")
        }

        var options: [CFString: Any] = [:]
        if format.isLossy { options[kCGImageDestinationLossyCompressionQuality] = quality }
        if let props = properties {
            if let o = props[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = o }
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                        kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary] {
                if let v = props[key] { options[key] = v }
            }
        }

        CGImageDestinationAddImage(dest, cg, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvertError("Couldn’t write the file. Check that the folder is writable.")
        }
    }

    private static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Draws the image over solid white (for transparent PNG -> JPG and PDF pages).
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        var spaces: [CGColorSpace] = []
        if let s = image.colorSpace, s.model == .rgb { spaces.append(s) }   // keep the original profile when possible
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) { spaces.append(srgb) }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        for space in spaces {
            guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(rect)
            ctx.draw(image, in: rect)
            if let result = ctx.makeImage() { return result }
        }
        return nil
    }

    // MARK: - Image -> PDF (PDFKit)

    private static func imageToPDF(_ url: URL, dir: URL, base: String) throws -> URL {
        guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
            throw ConvertError("Couldn’t read this image. It may be corrupt.")
        }
        let doc = PDFDocument()
        doc.insert(page, at: 0)
        let out = uniqueURL(in: dir, base: base, ext: "pdf")
        guard doc.write(to: out) else {
            throw ConvertError("Couldn’t write the PDF. Check that the folder is writable.")
        }
        return out
    }

    static func combineImagesToPDF(_ urls: [URL]) throws -> URL {
        let doc = PDFDocument()
        for url in urls {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
                throw ConvertError("Couldn’t read \(url.lastPathComponent). It may be corrupt.")
            }
            doc.insert(page, at: doc.pageCount)
        }
        let first = urls[0]
        let dir = AppSettings.outputDirectory(for: first)
        guard FileManager.default.isWritableFile(atPath: dir.path) else {
            throw ConvertError("No permission to save in “\(dir.lastPathComponent)”.")
        }
        let base = first.deletingPathExtension().lastPathComponent + "-combined"
        let out = uniqueURL(in: dir, base: base, ext: "pdf")
        guard doc.write(to: out) else {
            throw ConvertError("Couldn’t write the PDF. Check that the folder is writable.")
        }
        return out
    }

    // MARK: - PDF -> images (PDFKit)

    private static func pdfToImages(_ url: URL, format: OutputFormat, dir: URL, base: String, quality: Double) throws -> [URL] {
        guard let doc = PDFDocument(url: url) else {
            throw ConvertError("Couldn’t read this PDF. It may be corrupt.")
        }
        if doc.isLocked { throw ConvertError("This PDF is password protected.") }
        if doc.pageCount == 0 { throw ConvertError("This PDF has no pages.") }

        let multiPage = doc.pageCount > 1
        var targetDir = dir
        if multiPage {
            targetDir = uniqueFolder(in: dir, name: base)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        let digits = max(3, String(doc.pageCount).count)
        var outputs: [URL] = []

        for i in 0..<doc.pageCount {
            try autoreleasepool {
                guard let page = doc.page(at: i), let cg = render(page, scale: 2) else {
                    throw ConvertError("Couldn’t render page \(i + 1).")
                }
                let name = multiPage ? "\(base)-page-\(String(format: "%0\(digits)d", i + 1))" : base
                let out = uniqueURL(in: targetDir, base: name, ext: format.fileExtension)
                try write(cg, to: out, format: format, quality: quality, properties: nil, flatten: true)
                outputs.append(out)
            }
        }
        return multiPage ? [targetDir] : outputs
    }

    /// Renders one page at 2x (about 144 dpi).
    private static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        var size = page.bounds(for: .mediaBox).size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = page.thumbnail(of: target, for: .mediaBox)
        return thumb.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // MARK: - Originals

    /// Moves the original to the Trash (recoverable) after a successful conversion.
    private static func trashOriginal(_ url: URL, into summary: inout ConversionSummary) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            summary.failures.append(ConversionFailure(
                name: url.lastPathComponent,
                message: "Converted, but couldn’t move the original to the Trash."))
        }
    }

    // MARK: - Never overwrite

    private static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        OutputNaming.uniqueURL(dir: dir, base: base, ext: ext)
    }

    private static func uniqueFolder(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name, isDirectory: true)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name)-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}
