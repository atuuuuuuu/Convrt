import Foundation
import PDFKit

/// PDF tools: merge, split into pages, pull out the text. Offline, PDFKit only.
enum PDFTools {
    private static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            throw ToolError("Couldn’t read “\(url.lastPathComponent)”. It may be damaged or password-protected.")
        }
        return doc
    }

    private static func base(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    /// All pages of all PDFs, in the order given, as one new PDF next to the first.
    static func merge(_ urls: [URL]) throws -> URL {
        guard urls.count >= 2, let first = urls.first else { throw ToolError("Pick at least two PDFs to merge.") }
        let merged = PDFDocument()
        var index = 0
        for url in urls {
            let doc = try open(url)
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
                merged.insert(page, at: index)
                index += 1
            }
        }
        let out = OutputNaming.uniqueURL(dir: AppSettings.outputDirectory(for: first), base: base(first), suffix: "-merged", ext: "pdf")
        guard merged.write(to: out) else { throw ToolError("Couldn’t save the merged PDF. Check that the folder is writable.") }
        return out
    }

    /// One PDF per page, in a new folder next to the original. Returns the folder.
    static func split(_ url: URL) throws -> URL {
        let doc = try open(url)
        let dir = AppSettings.outputDirectory(for: url)
        let folder = OutputNaming.uniqueURL(dir: dir, base: base(url), suffix: " pages", ext: "")
        let width = String(doc.pageCount).count
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
                let single = PDFDocument()
                single.insert(page, at: 0)
                let number = String(format: "%0\(width)d", i + 1)
                guard single.write(to: folder.appendingPathComponent("\(base(url))-\(number).pdf")) else {
                    throw ToolError("Couldn’t save page \(i + 1).")
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    /// All the text, page after page, as a .txt next to the PDF.
    static func extractText(_ url: URL) throws -> URL {
        let doc = try open(url)
        let text = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ToolError("No text found in this PDF. It may be a scan, and reading text from pictures isn’t supported yet.")
        }
        let out = OutputNaming.uniqueURL(dir: AppSettings.outputDirectory(for: url), base: base(url), ext: "txt")
        do { try text.write(to: out, atomically: true, encoding: .utf8) }
        catch { throw ToolError("Couldn’t save the text file. Check that the folder is writable.") }
        return out
    }
}
