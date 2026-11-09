import XCTest
@testable import Convrt

final class WheelHitTestTests: XCTestCase {
    private let inner: CGFloat = 58
    private let outer: CGFloat = 150

    private func index(_ dx: CGFloat, _ dy: CGFloat, count: Int) -> Int? {
        WheelHitTest.wedgeIndex(dx: dx, dy: dy, count: count, inner: inner, outer: outer)
    }

    func testTopWedgeIsZero() {
        XCTAssertEqual(index(0, 100, count: 6), 0)
    }

    func testWedgesRunClockwiseFromTop() {
        XCTAssertEqual(index(100, 0, count: 4), 1)    // right
        XCTAssertEqual(index(0, -100, count: 4), 2)   // bottom
        XCTAssertEqual(index(-100, 0, count: 4), 3)   // left
    }

    func testInsideInnerRadiusIsNotAWedgeButIsCentre() {
        XCTAssertNil(index(10, 10, count: 6))
        XCTAssertTrue(WheelHitTest.isCentre(dx: 10, dy: 10, inner: inner))
        XCTAssertFalse(WheelHitTest.isCentre(dx: 0, dy: 100, inner: inner))
    }

    func testBeyondOuterRadiusPlusTolerance() {
        XCTAssertNotNil(index(0, 160, count: 6))      // within the 12 pt tolerance
        XCTAssertNil(index(0, 170, count: 6))
    }

    func testZeroItemsIsNil() {
        XCTAssertNil(index(0, 100, count: 0))
    }

    func testSingleItemCoversTheWholeRing() {
        XCTAssertEqual(index(0, 100, count: 1), 0)
        XCTAssertEqual(index(-100, -3, count: 1), 0)
    }

    func testTwelveItemsStayInRange() {
        for step in stride(from: 0.0, to: 360.0, by: 7.0) {
            let r = step * .pi / 180
            let i = index(CGFloat(sin(r)) * 100, CGFloat(cos(r)) * 100, count: 12)
            XCTAssertNotNil(i)
            XCTAssertTrue((0..<12).contains(i ?? -1))
        }
    }
}
