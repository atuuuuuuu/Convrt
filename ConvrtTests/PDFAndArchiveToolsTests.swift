import XCTest
import PDFKit
import AppKit
@testable import Convrt

final class PDFToolsTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    /// A real PDF with `pages` pages, each holding the text "page N <tag>".
    private func makePDF(_ name: String, pages: Int, tag: String = "") throws -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for n in 1...pages {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: "page \(n) \(tag)", attributes: [.font: NSFont.systemFont(ofSize: 24)]).draw(at: CGPoint(x: 20, y: 90))
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    func testMergeCombinesPagesInOrder() throws {
        let a = try makePDF("a.pdf", pages: 2, tag: "A"), b = try makePDF("b.pdf", pages: 3, tag: "B")
        let out = try PDFTools.merge([a, b])
        let doc = try XCTUnwrap(PDFDocument(url: out))
        XCTAssertEqual(doc.pageCount, 5)
        XCTAssertTrue(doc.page(at: 0)?.string?.contains("A") == true)
        XCTAssertTrue(doc.page(at: 4)?.string?.contains("B") == true)
        XCTAssertEqual(out.lastPathComponent, "a-merged.pdf")
    }

    func testMergeNeedsTwoFiles() throws {
        XCTAssertThrowsError(try PDFTools.merge([try makePDF("a.pdf", pages: 1)]))
    }

    func testMergeSkipsNothingSilentlyWhenOneIsCorrupt() throws {
        let bad = dir.appendingPathComponent("bad.pdf"); try Data([1, 2, 3]).write(to: bad)
        XCTAssertThrowsError(try PDFTools.merge([try makePDF("a.pdf", pages: 1), bad]))
    }

    func testSplitWritesOneFilePerPageInANewFolder() throws {
        let src = try makePDF("doc.pdf", pages: 3)
        let folder = try PDFTools.split(src)
        let files = try fm.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(files, ["doc-1.pdf", "doc-2.pdf", "doc-3.pdf"])
        XCTAssertEqual(PDFDocument(url: folder.appendingPathComponent("doc-2.pdf"))?.pageCount, 1)
        XCTAssertTrue(PDFDocument(url: folder.appendingPathComponent("doc-2.pdf"))?.string?.contains("page 2") == true)
        XCTAssertEqual(try PDFTools.split(src).lastPathComponent == folder.lastPathComponent, false, "second run must not reuse the folder")
    }

    func testExtractTextWritesTheWords() throws {
        let out = try PDFTools.extractText(try makePDF("t.pdf", pages: 2))
        let text = try String(contentsOf: out)
        XCTAssertTrue(text.contains("page 1") && text.contains("page 2"), text)
        XCTAssertEqual(out.pathExtension, "txt")
    }

    func testExtractTextFromImageOnlyPDFExplains() throws {
        let doc = PDFDocument()
        let image = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        doc.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let url = dir.appendingPathComponent("scan.pdf"); doc.write(to: url)
        XCTAssertThrowsError(try PDFTools.extractText(url)) {
            XCTAssertTrue($0.localizedDescription.lowercased().contains("no text"), $0.localizedDescription)
        }
    }

    func testCorruptPDFThrows() throws {
        let bad = dir.appendingPathComponent("bad.pdf"); try Data((0..<200).map { _ in UInt8.random(in: 0...255) }).write(to: bad)
        XCTAssertThrowsError(try PDFTools.split(bad))
        XCTAssertThrowsError(try PDFTools.extractText(bad))
    }
}

final class ArchiveToolsTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func write(_ rel: String, _ text: String = "hi") throws -> URL {
        let url = dir.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testZipFolderThenUnzipRoundTrips() throws {
        _ = try write("Photos/a.txt", "AAA"); _ = try write("Photos/sub/b.txt", "BBB")
        let zip = try ArchiveTools.zip([dir.appendingPathComponent("Photos")])
        XCTAssertEqual(zip.lastPathComponent, "Photos.zip")
        try fm.removeItem(at: dir.appendingPathComponent("Photos"))
        let out = try ArchiveTools.unzip(zip)
        XCTAssertEqual(out.lastPathComponent, "Photos", "a single top-level folder is not nested again")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("sub/b.txt")), "BBB")
    }

    func testZipSeveralFilesFromOneFolder() throws {
        let a = try write("a.txt"), b = try write("b.txt")
        let zip = try ArchiveTools.zip([a, b])
        let out = try ArchiveTools.unzip(zip)
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("a.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("b.txt").path))
    }

    func testZipFromDifferentFoldersIsExplained() throws {
        let a = try write("one/a.txt"), b = try write("two/b.txt")
        XCTAssertThrowsError(try ArchiveTools.zip([a, b])) {
            XCTAssertTrue($0.localizedDescription.contains("same folder"), $0.localizedDescription)
        }
    }

    func testZipNeverOverwritesAndUnzipNeverMerges() throws {
        let f = try write("Docs/x.txt")
        let first = try ArchiveTools.zip([f.deletingLastPathComponent()])
        let second = try ArchiveTools.zip([f.deletingLastPathComponent()])
        XCTAssertNotEqual(first, second)
        let a = try ArchiveTools.unzip(first), b = try ArchiveTools.unzip(first)
        XCTAssertNotEqual(a, b)
    }

    func testUnzipRefusesToWriteOutsideItsFolder() throws {
        // A "zip slip" archive: one entry tries to escape with "../".
        let zip = dir.appendingPathComponent("evil.zip")
        let script = "import zipfile,sys\nz=zipfile.ZipFile(sys.argv[1],'w')\nz.writestr('../escaped.txt','x')\nz.writestr('ok.txt','y')\nz.close()\n"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", script, zip.path]; try p.run(); p.waitUntilExit()
        try XCTSkipUnless(fm.fileExists(atPath: zip.path), "python3 not available to craft the archive")
        _ = try? ArchiveTools.unzip(zip)
        XCTAssertFalse(fm.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("escaped.txt").path))
    }

    func testCorruptZipFailsWithoutLeavingJunk() throws {
        let bad = dir.appendingPathComponent("bad.zip"); try Data((0..<100).map { _ in UInt8.random(in: 0...255) }).write(to: bad)
        let before = try fm.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertThrowsError(try ArchiveTools.unzip(bad))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: dir.path).sorted(), before)
    }

    func testCatalogOffersArchiveAndPDFTools() {
        func tools(_ names: [String]) -> [ItemAction] {
            WheelCatalog.items(for: .tools, urls: names.map { URL(fileURLWithPath: "/tmp/\($0)") }).map(\.action)
        }
        XCTAssertTrue(tools(["a.zip"]).contains(.tool(.unzip)))
        XCTAssertFalse(tools(["a.pdf"]).contains(.tool(.unzip)))
        XCTAssertEqual(tools(["a.pdf"]), [.tool(.splitPDF), .tool(.extractText), .tool(.zip), .tool(.info)])
        XCTAssertTrue(tools(["a.pdf", "b.pdf"]).contains(.tool(.mergePDF)))
        XCTAssertEqual(tools(["notes.txt"]), [.tool(.zip), .tool(.info)])
    }
}
