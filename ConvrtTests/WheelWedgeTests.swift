import XCTest
import SwiftUI
@testable import Convrt

final class WheelWedgeTests: XCTestCase {
    let rect = CGRect(x: 0, y: 0, width: 360, height: 360)
    var centre: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    func testNormalWedgeLeavesTheCentreEmpty() {
        let p = WheelWedge(index: 0, count: 8, innerRadius: 58, outerRadius: 150).path(in: rect)
        XCTAssertFalse(p.contains(centre))
        XCTAssertTrue(p.contains(CGPoint(x: centre.x, y: centre.y - 100)))   // wedge 0 is at the top
    }

    // Reported on r/SwiftUI: with a small inner radius or many wedges the inner arc flipped
    // and every wedge covered the middle of the wheel.
    func testSmallInnerRadiusDoesNotFillTheCentre() {
        for i in 0..<12 {
            let p = WheelWedge(index: i, count: 12, innerRadius: 10, outerRadius: 150).path(in: rect)
            XCTAssertFalse(p.contains(centre), "wedge \(i) covers the centre")
        }
    }
}
