import Foundation

/// Runs one tool over every dragged file. Call from a background queue.
/// One bad file never stops the others; each file's result lands next to the original.
enum ToolEngine {
    static func run(_ id: ToolID, urls: [URL]) -> ConversionSummary {
        var summary = ConversionSummary()

        switch id {
        case .mergePDF:
            let allPDFs = urls.allSatisfy { FormatCatalog.kind(of: $0) == .pdf }
            do { summary.outputs.append(allPDFs ? try PDFTools.merge(urls) : try ImageTools.mergeToPDF(urls)) }
            catch { summary.failures.append(ConversionFailure(name: "Merge PDF", message: error.localizedDescription)) }
            return summary
        case .zip:
            do { summary.outputs.append(try ArchiveTools.zip(urls)) }
            catch { summary.failures.append(ConversionFailure(name: "Zip", message: error.localizedDescription)) }
            return summary
        case .info:
            summary.detail = urls.map(FileInfo.describe).joined(separator: "\n\n")
            summary.message = "Info"
            return summary
        default:
            break
        }

        for url in urls {
            do { summary.outputs.append(try apply(id, to: url)) }
            catch { summary.failures.append(ConversionFailure(name: url.lastPathComponent, message: error.localizedDescription)) }
        }
        return summary
    }

    /// Trims every video to the same start and end (the end is cut back to each clip's own length).
    static func trim(urls: [URL], start: Double, end: Double) -> ConversionSummary {
        var summary = ConversionSummary()
        for url in urls {
            do { summary.outputs.append(try VideoTools.trim(url, from: start, to: end)) }
            catch { summary.failures.append(ConversionFailure(name: url.lastPathComponent, message: error.localizedDescription)) }
        }
        return summary
    }

    private static func apply(_ id: ToolID, to url: URL) throws -> URL {
        switch id {
        case .compress:         return try ImageTools.compress(url, quality: AppSettings.compressQuality)
        case .resize:           return try ImageTools.resize(url, maxDimension: AppSettings.toolMaxDimension)
        case .stripMetadata:    return try ImageTools.stripMetadata(url)
        case .rotateLeft:       return try ImageTools.rotate(url, quarterTurnsClockwise: -1)
        case .rotateRight:      return try ImageTools.rotate(url, quarterTurnsClockwise: 1)
        case .flipHorizontal:   return try ImageTools.flip(url, horizontal: true)
        case .cropSquare:       return try ImageTools.cropSquare(url)
        case .removeBackground: return try ImageTools.removeBackground(url)
        case .mute:             return try VideoTools.mute(url)
        case .snapshot:         return try VideoTools.snapshot(url)
        case .extractAudio:
            return try VideoTools.extractAudio(url, to: .m4a, dir: AppSettings.outputDirectory(for: url),
                                               base: url.deletingPathExtension().lastPathComponent)
        case .splitPDF:         return try PDFTools.split(url)
        case .extractText:      return try PDFTools.extractText(url)
        case .unzip:            return try ArchiveTools.unzip(url)
        case .trim:             throw ToolError("Trim needs a start and an end time.")
        case .crop:             throw ToolError("Crop opens its own window.")
        case .mergePDF, .zip, .info: throw ToolError("Handled elsewhere.")
        }
    }
}
