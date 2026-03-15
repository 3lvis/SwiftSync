import SwiftUI
import SwiftData
import DemoCore
import SwiftSync
#if canImport(UIKit)
import UIKit
#endif

@main
struct DemoApp: App {
    @State private var runtime = DemoRuntime()

    init() {
#if canImport(UIKit)
        if ProcessInfo.processInfo.environment["SWIFTSYNC_UI_TESTING"] == "1" {
            UIView.setAnimationsEnabled(false)
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(runtime: runtime)
        }
        .modelContainer(runtime.syncContainer.modelContainer)
    }
}
