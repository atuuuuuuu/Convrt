import XCTest
@testable import Convrt

final class ShellQuoteTests: XCTestCase {
    func testSingleQuoteEscapes() {
        XCTAssertEqual(ShellQuote.single("it's a \"file\""), "'it'\\''s a \"file\"'")
    }
    func testSingleQuoteEmpty() { XCTAssertEqual(ShellQuote.single(""), "''") }
    func testSingleQuotePlain() { XCTAssertEqual(ShellQuote.single("plain"), "'plain'") }
}

final class ActionRunnerTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("locked").path)
        try? fm.removeItem(at: root)
    }

    private func makeFile(_ name: String, in dir: URL? = nil, text: String = "x") throws -> URL {
        let url = (dir ?? root).appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCopyPathJoinsWithNewline() throws {
        let a = URL(fileURLWithPath: "/tmp/it's here.png"), b = URL(fileURLWithPath: "/tmp/b.png")
        XCTAssertEqual(ActionRunner.copyPathText(for: [a, b]), "/tmp/it's here.png\n/tmp/b.png")
    }

    func testTerminalDirectoryForFileIsParent() throws {
        let f = try makeFile("a b.png")
        XCTAssertEqual(ActionRunner.terminalDirectory(for: f).standardizedFileURL.path, root.standardizedFileURL.path)
    }

    func testTerminalDirectoryForFolderIsItself() throws {
        let d = try makeDir("sub")
        XCTAssertEqual(ActionRunner.terminalDirectory(for: d).standardizedFileURL.path, d.standardizedFileURL.path)
    }

    func testTransferCopyKeepsOriginal() throws {
        let src = try makeFile("a.txt"), dest = try makeDir("dest")
        let s = ActionRunner.transfer(urls: [src], to: dest, move: false)
        XCTAssertEqual(s.failures.count, 0)
        XCTAssertTrue(fm.fileExists(atPath: src.path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
    }

    func testTransferMoveRemovesOriginal() throws {
        let src = try makeFile("a.txt"), dest = try makeDir("dest")
        let s = ActionRunner.transfer(urls: [src], to: dest, move: true)
        XCTAssertEqual(s.failures.count, 0)
        XCTAssertFalse(fm.fileExists(atPath: src.path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
    }

    func testTransferNeverOverwrites() throws {
        let src = try makeFile("a.txt", text: "new"), dest = try makeDir("dest")
        _ = try makeFile("a.txt", in: dest, text: "old")
        let s = ActionRunner.transfer(urls: [src], to: dest, move: false)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("a.txt")), "old")
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("a-1.txt")), "new")
        XCTAssertEqual(s.outputs.map(\.lastPathComponent), ["a-1.txt"])
    }

    func testTransferFolderKeepsItsName() throws {
        let folder = try makeDir("My.Folder"), dest = try makeDir("dest")
        _ = try makeFile("inside.txt", in: folder)
        let s = ActionRunner.transfer(urls: [folder], to: dest, move: false)
        XCTAssertEqual(s.failures.count, 0)
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("My.Folder/inside.txt").path))
    }

    func testTransferReadOnlyDestinationReportsFailure() throws {
        let src = try makeFile("a.txt"), locked = try makeDir("locked")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let s = ActionRunner.transfer(urls: [src], to: locked, move: false)
        XCTAssertEqual(s.outputs.count, 0)
        XCTAssertEqual(s.failures.count, 1)
    }

    func testTransferContinuesPastOneBadFile() throws {
        let good = try makeFile("good.txt"), dest = try makeDir("dest")
        let missing = root.appendingPathComponent("missing.txt")
        let s = ActionRunner.transfer(urls: [missing, good], to: dest, move: false)
        XCTAssertEqual(s.failures.count, 1)
        XCTAssertEqual(s.outputs.map(\.lastPathComponent), ["good.txt"])
    }

    func testMovedFilesAreNeverUndoable() throws {
        let src = try makeFile("a.txt"), dest = try makeDir("dest")
        XCTAssertFalse(ActionRunner.transfer(urls: [src], to: dest, move: true).undoable)
        XCTAssertTrue(ActionRunner.transfer(urls: [try makeFile("b.txt")], to: dest, move: false).undoable)
    }

    func testMoveIntoSameFolderIsReportedNotRenamed() throws {
        let src = try makeFile("a.txt")
        let s = ActionRunner.transfer(urls: [src], to: root, move: true)
        XCTAssertEqual(s.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: src.path))
    }
}
