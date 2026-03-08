import SwiftUI
import DemoCore
import SwiftSync

struct ContentView: View {
    @ObservedObject var runtime: DemoRuntime

    var body: some View {
        ProjectsView(syncContainer: runtime.syncContainer, syncEngine: runtime.syncEngine)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Scenario", selection: $runtime.scenario) {
                    ForEach(DemoNetworkScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
