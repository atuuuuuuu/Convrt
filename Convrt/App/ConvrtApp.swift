import SwiftUI

@main
struct ConvrtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible windows at launch. The menu bar item is created in AppDelegate.
        Settings { EmptyView() }
    }
}
    