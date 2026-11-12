import XCTest
@testable import Convrt

final class PermissionManagerTests: XCTestCase {
    func testResetCommandsCoverAccessibilityAndInputMonitoring() {
        let id = "atu.testing.Convrt"
        XCTAssertEqual(PermissionManager.resetCommands(bundleID: id), [
            ["tccutil", "reset", "Accessibility", id],
            ["tccutil", "reset", "ListenEvent", id]
        ])
    }

    func testAccessibilityListNameFollowsTheMacOS27Rename() {
        func name(_ major: Int) -> String {
            PermissionManager.accessibilityListName(for: OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0))
        }
        XCTAssertEqual(name(13), "Accessibility")
        XCTAssertEqual(name(26), "Accessibility")
        XCTAssertEqual(name(27), "Device Control and Data Access")
    }
}

final class AppEnvironmentTests: XCTestCase {
    func testIsRunningTestsIsTrueUnderXCTest() {
        XCTAssertTrue(AppEnvironment.isRunningTests)
    }
}
