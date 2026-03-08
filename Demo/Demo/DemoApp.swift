import SwiftUI
import SwiftData
import DemoCore
import SwiftSync

@main
struct DemoApp: App {
    @State private var runtime = DemoRuntime()

    var body: some Scene {
        WindowGroup {
            ContentView(runtime: runtime)
        }
        .modelContainer(runtime.syncContainer.modelContainer)
    }
}
