import XCTest
@testable import Convrt

final class ThemeTests: XCTestCase {
    func testPaletteMatchesSpec() {
        XCTAssertEqual(Theme.hex(for: .primary), 0x2F7BFF)
        XCTAssertEqual(Theme.hex(for: .navy), 0x0B1B3A)
        XCTAssertEqual(Theme.hex(for: .ice), 0xEAF2FF)
        XCTAssertEqual(Theme.hex(for: .glow), 0x6FA8FF)
    }

    func testHexComponentsAreNormalized() {
        let c = Theme.components(hex: 0x2F7BFF)
        XCTAssertEqual(c.red, 0x2F / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.green, 0x7B / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.blue, 1.0, accuracy: 0.0001)
    }
}
