import SwiftUI
import SwiftData
import DemoCore
import SwiftSync

@main
struct DemoApp: App {
    @StateObject private var runtime = DemoRuntime()

    var body: some Scene {
        WindowGroup {
            DemoView(runtime: runtime)
        }
        .modelContainer(runtime.syncContainer.modelContainer)
    }
}
