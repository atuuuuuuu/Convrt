import XCTest
@testable import Convrt

final class ShelfModelTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func file(_ name: String) throws -> URL {
        let u = dir.appendingPathComponent(name)
        try "x".write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func testAddKeepsOrderAndSkipsDuplicates() throws {
        let m = ShelfModel()
        let a = try file("a.txt"), b = try file("b.txt")
        m.add([a, b]); m.add([a])
        XCTAssertEqual(m.urls.map(\.lastPathComponent), ["a.txt", "b.txt"])
    }

    func testAddIgnoresFilesThatDoNotExist() throws {
        let m = ShelfModel()
        m.add([dir.appendingPathComponent("ghost.txt"), try file("real.txt")])
        XCTAssertEqual(m.urls.map(\.lastPathComponent), ["real.txt"])
    }

    func testSameFileThroughASymlinkedPathCountsOnce() throws {
        let m = ShelfModel()
        let a = try file("a.txt")
        m.add([a, URL(fileURLWithPath: "/private" + a.path)].filter { fm.fileExists(atPath: $0.path) })
        XCTAssertEqual(m.urls.count, 1)
    }

    func testRemoveAndClear() throws {
        let m = ShelfModel()
        let a = try file("a.txt"), b = try file("b.txt")
        m.add([a, b]); m.remove(a)
        XCTAssertEqual(m.urls.map(\.lastPathComponent), ["b.txt"])
        m.clear()
        XCTAssertTrue(m.urls.isEmpty)
    }

    func testPruneDropsFilesThatWereDeleted() throws {
        let m = ShelfModel()
        let a = try file("a.txt"), b = try file("b.txt")
        m.add([a, b]); try fm.removeItem(at: a)
        m.pruneMissing()
        XCTAssertEqual(m.urls.map(\.lastPathComponent), ["b.txt"])
    }
}

final class DropZoneModelTests: XCTestCase {
    private func img(_ n: String = "a.png") -> URL { URL(fileURLWithPath: "/tmp/\(n)") }

    func testStartsEmpty() {
        let m = DropZoneModel()
        XCTAssertTrue(m.urls.isEmpty)
        XCTAssertTrue(m.items.isEmpty)
        XCTAssertTrue(m.availableKinds.isEmpty)
    }

    func testDroppingAnImageOffersAllThreeWheels() {
        let m = DropZoneModel()
        m.ingest([img()])
        XCTAssertEqual(m.availableKinds, [.convert, .tools, .actions])
        XCTAssertEqual(m.kind, .convert)
        XCTAssertFalse(m.items.isEmpty)
    }

    func testFolderStartsOnTheFirstWheelThatHasItems() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let m = DropZoneModel()
        m.ingest([dir])
        XCTAssertEqual(m.kind, .tools)
    }

    func testSelectingAnUnavailableWheelIsIgnored() {
        let m = DropZoneModel()
        m.ingest([img("a.zip")])           // convert is empty for a zip
        m.select(.convert)
        XCTAssertNotEqual(m.kind, .convert)
    }

    func testDroppingMoreFilesMergesWithoutDuplicates() {
        let m = DropZoneModel()
        m.ingest([img("a.png")]); m.ingest([img("a.png"), img("b.png")])
        XCTAssertEqual(m.urls.map(\.lastPathComponent), ["a.png", "b.png"])
    }

    func testClearResetsEverything() {
        let m = DropZoneModel()
        m.ingest([img()]); m.select(.actions); m.clear()
        XCTAssertTrue(m.urls.isEmpty); XCTAssertEqual(m.kind, .convert); XCTAssertTrue(m.items.isEmpty)
    }

    func testMixingTypesNarrowsTheItems() {
        let m = DropZoneModel()
        m.ingest([img("a.png")])
        let before = m.items.count
        m.ingest([URL(fileURLWithPath: "/tmp/b.mp3")])
        XCTAssertLessThan(m.items.count, before, "an image and a song share fewer conversions than an image alone")
    }

    func testFloatActionIsOnTheActionsWheel() {
        let actions = WheelCatalog.items(for: .actions, urls: [img()]).map(\.action)
        XCTAssertTrue(actions.contains(.action(.floatShelf)))
    }
}
