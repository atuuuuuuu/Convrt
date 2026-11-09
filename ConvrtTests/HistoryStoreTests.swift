import XCTest
@testable import Convrt

final class HistoryStoreTests: XCTestCase {
    private var dir: URL!
    private var file: URL { dir.appendingPathComponent("history.json") }
    private let fm = FileManager.default
    private var trashed: [URL] = []

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        trashed = []
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func store(limit: Int = 20) -> HistoryStore {
        HistoryStore(fileURL: file, limit: limit, trash: { [unowned self] url in
            self.trashed.append(url)
            try self.fm.removeItem(at: url)          // stand-in for the Trash, so tests never touch the real one
        })
    }

    private func output(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testNewestFirstAndLimit() throws {
        let s = store(limit: 3)
        for i in 1...5 { s.record(title: "job \(i)", outputs: [try output("o\(i).png")]) }
        XCTAssertEqual(s.entries.map(\.title), ["job 5", "job 4", "job 3"])
    }

    func testIgnoresRunsWithNoOutputs() {
        let s = store()
        s.record(title: "AirDrop", outputs: [])
        XCTAssertTrue(s.entries.isEmpty)
    }

    func testPersistsAcrossInstances() throws {
        store().record(title: "PNG", outputs: [try output("a.png")])
        let again = store()
        XCTAssertEqual(again.entries.map(\.title), ["PNG"])
        XCTAssertEqual(again.entries.first?.outputs.map(\.lastPathComponent), ["a.png"])
    }

    func testUndoTrashesOutputsAndForgetsTheEntry() throws {
        let s = store()
        let a = try output("a.png"), b = try output("b.png")
        s.record(title: "PNG", outputs: [a, b])
        let result = s.undo(try XCTUnwrap(s.entries.first).id)
        XCTAssertEqual(result.trashed, 2)
        XCTAssertEqual(Set(trashed.map(\.lastPathComponent)), ["a.png", "b.png"])
        XCTAssertTrue(s.entries.isEmpty)
    }

    func testUndoSkipsFilesThatAreAlreadyGone() throws {
        let s = store()
        let a = try output("a.png"), b = try output("b.png")
        s.record(title: "PNG", outputs: [a, b])
        try fm.removeItem(at: a)
        let result = s.undo(try XCTUnwrap(s.entries.first).id)
        XCTAssertEqual(result.trashed, 1)
        XCTAssertEqual(result.missing, 1)
    }

    func testUndoReportsFailuresAndKeepsGoing() throws {
        let failing = HistoryStore(fileURL: file, limit: 5, trash: { url in
            if url.lastPathComponent == "a.png" { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
        failing.record(title: "PNG", outputs: [try output("a.png"), try output("b.png")])
        let result = failing.undo(try XCTUnwrap(failing.entries.first).id)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.trashed, 1)
    }

    func testUndoUnknownIDDoesNothing() {
        let result = store().undo(UUID())
        XCTAssertEqual(result.trashed + result.missing + result.failed, 0)
    }

    func testCorruptHistoryFileStartsEmpty() throws {
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(store().entries.isEmpty)
    }

    func testClearEmptiesAndPersists() throws {
        let s = store()
        s.record(title: "PNG", outputs: [try output("a.png")])
        s.clear()
        XCTAssertTrue(s.entries.isEmpty)
        XCTAssertTrue(store().entries.isEmpty)
    }

    func testEntryKeepsTitleDateAndCount() throws {
        let s = store()
        s.record(title: "Compress", outputs: [try output("a.jpg"), try output("b.jpg")])
        let e = try XCTUnwrap(s.entries.first)
        XCTAssertEqual(e.title, "Compress")
        XCTAssertEqual(e.outputs.count, 2)
        XCTAssertLessThan(abs(e.date.timeIntervalSinceNow), 5)
    }
}
