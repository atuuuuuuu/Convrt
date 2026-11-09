import XCTest
@testable import Convrt

final class WheelStateTests: XCTestCase {
    private func image(_ name: String = "a.heic") -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCycleOrderIsConvertToolsActions() {
        var s = WheelState(urls: [image()])
        XCTAssertEqual(s.kind, .convert)
        s.cycle(); XCTAssertEqual(s.kind, .tools)
        s.cycle(); XCTAssertEqual(s.kind, .actions)
        s.cycle(); XCTAssertEqual(s.kind, .convert)
    }

    func testCycleSkipsEmptyWheels() throws {
        // A folder has nothing to convert, so the wheels are Tools and Actions only.
        var s = WheelState(urls: [try folder()])
        XCTAssertEqual(s.availableKinds, [.tools, .actions])
        XCTAssertEqual(s.kind, .tools, "starts on the first wheel that has items")
        s.cycle(); XCTAssertEqual(s.kind, .actions)
        s.cycle(); XCTAssertEqual(s.kind, .tools)
    }

    func testCycleWithNoValidWheelsIsNoOp() {
        var s = WheelState(urls: [])
        XCTAssertTrue(s.availableKinds.isEmpty)
        s.cycle()
        XCTAssertEqual(s.kind, .convert)
        XCTAssertTrue(s.items.isEmpty)
    }

    func testStepWrapsBothDirections() {
        var s = WheelState(urls: [image()])
        let n = s.items.count
        XCTAssertGreaterThan(n, 1)
        s.step(1);  XCTAssertEqual(s.highlighted, 0)
        s.step(-1); XCTAssertEqual(s.highlighted, n - 1)
        s.step(1);  XCTAssertEqual(s.highlighted, 0)
    }

    func testStepFromNilStartsAtFirstOrLast() {
        var forward = WheelState(urls: [image()])
        forward.step(1)
        XCTAssertEqual(forward.highlighted, 0)

        var backward = WheelState(urls: [image()])
        backward.step(-1)
        XCTAssertEqual(backward.highlighted, backward.items.count - 1)
    }

    func testStepOnEmptyItemsKeepsNil() {
        var s = WheelState(urls: [])
        s.step(1); XCTAssertNil(s.highlighted)
        s.step(-1); XCTAssertNil(s.highlighted)
    }

    func testNextIndexOnSingleItemWheelStaysOnIt() {
        // No wheel has exactly one item any more, so test the stepping rule itself.
        XCTAssertEqual(WheelState.nextIndex(current: nil, delta: 1, count: 1), 0)
        XCTAssertEqual(WheelState.nextIndex(current: 0, delta: 1, count: 1), 0)
        XCTAssertEqual(WheelState.nextIndex(current: 0, delta: -1, count: 1), 0)
        XCTAssertNil(WheelState.nextIndex(current: nil, delta: 1, count: 0))
        XCTAssertEqual(WheelState.nextIndex(current: 2, delta: 7, count: 5), 4)
        XCTAssertEqual(WheelState.nextIndex(current: 1, delta: -3, count: 5), 3)
    }

    func testJumpToEmptyWheelIgnored() throws {
        var s = WheelState(urls: [try folder()])
        s.jump(to: .convert)
        XCTAssertEqual(s.kind, .tools)
    }

    func testJumpSwitchesToAvailableWheel() {
        var s = WheelState(urls: [image()])
        s.jump(to: .actions)
        XCTAssertEqual(s.kind, .actions)
    }

    func testCycleResetsHighlight() {
        var s = WheelState(urls: [image()])
        s.step(1)
        XCTAssertNotNil(s.highlighted)
        s.cycle()
        XCTAssertNil(s.highlighted)
    }

    func testHighlightedItemFollowsHighlight() {
        var s = WheelState(urls: [image()])
        XCTAssertNil(s.highlightedItem)
        s.step(1)
        XCTAssertEqual(s.highlightedItem, s.items[0])
    }

    func testWheelsNeverExceedTwelveItems() {
        let many = (0..<3).map { image("p\($0).png") }
        for kind in WheelKind.allCases {
            XCTAssertLessThanOrEqual(WheelCatalog.items(for: kind, urls: many).count, 12)
        }
    }

    func testMergePDFOnlyOfferedForTwoOrMoreImages() {
        let one = WheelCatalog.items(for: .tools, urls: [image("a.png")])
        let two = WheelCatalog.items(for: .tools, urls: [image("a.png"), image("b.png")])
        XCTAssertFalse(one.contains { $0.action == .tool(.mergePDF) })
        XCTAssertTrue(two.contains { $0.action == .tool(.mergePDF) })
    }

    func testImageToolsHiddenForMixedSelection() {
        let mixed = WheelCatalog.items(for: .tools, urls: [image("a.png"), URL(fileURLWithPath: "/tmp/b.pdf")])
        XCTAssertEqual(mixed.map(\.action), [.tool(.zip), .tool(.info)])
    }

    func testConvertWheelMatchesFormatCatalog() {
        let urls = [image("a.heic")]
        let expected = FormatCatalog.formats(for: urls).map { ItemAction.convert($0) }
        XCTAssertEqual(WheelCatalog.items(for: .convert, urls: urls).map(\.action), expected)
    }

    func testActionsAvailableForAnyFileIncludingAirDrop() throws {
        let items = WheelCatalog.items(for: .actions, urls: [try folder()])
        XCTAssertTrue(items.contains { $0.action == .action(.airDrop) })
        XCTAssertTrue(items.contains { $0.action == .action(.copyPath) })
    }
}
