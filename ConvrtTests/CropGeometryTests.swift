import XCTest
@testable import Convrt

final class CropGeometryTests: XCTestCase {
    private func geo(_ w: CGFloat = 400, _ h: CGFloat = 200) -> CropGeometry {
        CropGeometry(bounds: CGSize(width: w, height: h))
    }

    func testStartsAsCentered80PercentOfTheImage() {
        let g = geo()
        XCTAssertEqual(g.rect, CGRect(x: 40, y: 20, width: 320, height: 160))
    }

    func testDragRightEdgeGrowsWidth() {
        var g = geo(); g.drag(.right, by: CGSize(width: 20, height: 99))
        XCTAssertEqual(g.rect.maxX, 380, accuracy: 0.001)
        XCTAssertEqual(g.rect.height, 160, "a side handle never changes the other axis")
    }

    func testDraggingPastTheImageIsClamped() {
        var g = geo(); g.drag(.left, by: CGSize(width: -1000, height: 0))
        XCTAssertEqual(g.rect.minX, 0, accuracy: 0.001)
        g.drag(.bottom, by: CGSize(width: 0, height: 1000))
        XCTAssertEqual(g.rect.maxY, 200, accuracy: 0.001)
    }

    func testMinimumSideIsEnforced() {
        var g = geo(); g.drag(.right, by: CGSize(width: -1000, height: 0))
        XCTAssertEqual(g.rect.width, CropGeometry.minSide, accuracy: 0.001)
    }

    func testMoveKeepsSizeAndStaysInside() {
        var g = geo(); let size = g.rect.size
        g.drag(.move, by: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(g.rect.size, size)
        XCTAssertEqual(g.rect.maxX, 400, accuracy: 0.001)
        XCTAssertEqual(g.rect.maxY, 200, accuracy: 0.001)
        g.drag(.move, by: CGSize(width: -5000, height: -5000))
        XCTAssertEqual(g.rect.origin, .zero)
    }

    func testCornerDragKeepsSquareRatio() {
        var g = geo(); g.setAspect(1)
        g.drag(.bottomRight, by: CGSize(width: -30, height: -5))
        XCTAssertEqual(g.rect.width, g.rect.height, accuracy: 0.01)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 200).contains(g.rect))
    }

    func testEdgeDragKeepsRatioByAdjustingTheOtherSide() {
        var g = geo(); g.setAspect(2)
        g.drag(.right, by: CGSize(width: -40, height: 0))
        XCTAssertEqual(g.rect.width / g.rect.height, 2, accuracy: 0.01)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 200).contains(g.rect))
    }

    func testCornerDragOutwardIsClampedToTheImageAndKeepsRatio() {
        var g = geo(); g.setAspect(16.0 / 9.0)
        g.drag(.topLeft, by: CGSize(width: -5000, height: -5000))
        XCTAssertEqual(g.rect.width / g.rect.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 200).insetBy(dx: -0.01, dy: -0.01).contains(g.rect))
    }

    func testSetAspectSquareFitsInsideTheImage() {
        var g = geo(); g.setAspect(1)
        XCTAssertEqual(g.rect.width, g.rect.height, accuracy: 0.01)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 200).contains(g.rect))
    }

    func testClearingAspectKeepsTheRect() {
        var g = geo(); g.setAspect(1); let r = g.rect
        g.setAspect(nil)
        XCTAssertEqual(g.rect, r)
        XCTAssertNil(g.aspect)
    }

    func testPresetRatios() {
        let size = CGSize(width: 300, height: 200)
        XCTAssertNil(CropGeometry.Preset.free.ratio(for: size))
        XCTAssertEqual(CropGeometry.Preset.original.ratio(for: size)!, 1.5, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.Preset.square.ratio(for: size)!, 1, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.Preset.sixteenNine.ratio(for: size)!, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.Preset.a4Portrait.ratio(for: size)!, 210.0 / 297.0, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.Preset.a4Landscape.ratio(for: size)!, 297.0 / 210.0, accuracy: 0.0001)
    }

    func testPixelRectIsWholePixelsAndInsideTheImage() {
        var g = geo(); g.drag(.right, by: CGSize(width: 0.37, height: 0))
        let r = g.pixelRect
        XCTAssertEqual(r, r.integral)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 200).contains(r))
    }

    func testResetCoversTheWholeImageWhenFree() {
        var g = geo(); g.drag(.move, by: CGSize(width: 30, height: 10))
        g.reset()
        XCTAssertEqual(g.rect, CGRect(x: 0, y: 0, width: 400, height: 200))
    }

    func testTinyImageDoesNotCrash() {
        var g = CropGeometry(bounds: CGSize(width: 10, height: 10))
        g.drag(.bottomRight, by: CGSize(width: 5, height: 5))
        g.setAspect(16.0 / 9.0)
        XCTAssertFalse(g.rect.isNull)
        XCTAssertTrue(g.rect.width > 0 && g.rect.height > 0)
    }
}
