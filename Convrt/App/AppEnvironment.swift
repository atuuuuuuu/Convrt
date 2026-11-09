import Foundation

enum AppEnvironment {
    /// True when running under XCTest (Xcode's test host or `swift test`). The app must stay silent then:
    /// no menu bar icon, no drag monitor, no permission dialog on the developer's screen.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
