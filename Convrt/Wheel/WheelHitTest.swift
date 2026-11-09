import CoreGraphics
import Foundation

/// Pure geometry for the donut: which wedge is under a point (relative to the wheel's centre, y pointing up).
enum WheelHitTest {
    /// Extra reach beyond the outer radius so edge wedges are easy to hit.
    static let outerTolerance: CGFloat = 12

    /// Wedge 0 is centred at the top; wedges run clockwise.
    static func wedgeIndex(dx: CGFloat, dy: CGFloat, count: Int, inner: CGFloat, outer: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        let dist = hypot(dx, dy)
        guard dist >= inner && dist <= outer + outerTolerance else { return nil }

        var deg = Double(atan2(dx, dy)) * 180 / .pi     // clockwise from the top
        if deg < 0 { deg += 360 }
        let slice = 360.0 / Double(count)
        let index = Int(((deg + slice / 2).truncatingRemainder(dividingBy: 360)) / slice)
        return min(index, count - 1)
    }

    static func isCentre(dx: CGFloat, dy: CGFloat, inner: CGFloat) -> Bool {
        hypot(dx, dy) < inner
    }
}
