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
}

final class AppEnvironmentTests: XCTestCase {
    func testIsRunningTestsIsTrueUnderXCTest() {
        XCTAssertTrue(AppEnvironment.isRunningTests)
    }
}
