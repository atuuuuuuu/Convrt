import XCTest
import AppKit
@testable import Convrt

final class WheelKeyMappingTests: XCTestCase {
    private func keys(_ pressed: NSEvent.ModifierFlags, trigger: NSEvent.ModifierFlags = .shift,
                      option: Bool = true, direct: Bool = true) -> [WheelKey] {
        DragMonitor.keys(for: pressed, trigger: trigger, optionCycles: option, directJump: direct)
    }

    func testOptionCycles() { XCTAssertEqual(keys(.option), [.cycle]) }
    func testCommandAndControlJump() {
        XCTAssertEqual(keys(.command), [.tools])
        XCTAssertEqual(keys(.control), [.actions])
    }
    func testTheTriggerKeyItselfDoesNothing() {
        XCTAssertEqual(keys(.shift), [])
        XCTAssertEqual(keys(.option, trigger: .option), [], "the key that opened the wheel never doubles as a wheel key")
    }
    func testSettingsCanTurnThemOff() {
        XCTAssertEqual(keys(.option, option: false), [])
        XCTAssertEqual(keys([.command, .control], direct: false), [])
    }
    func testNothingPressedMeansNoKeys() { XCTAssertEqual(keys([]), []) }
    func testOptionAndShiftTogetherIsJustACycle() { XCTAssertEqual(keys([.option, .shift]), [.cycle]) }
}
