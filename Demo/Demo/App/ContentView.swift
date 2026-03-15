import SwiftUI
import DemoCore
import Observation
import SwiftSync

struct ContentView: View {
    @Bindable var runtime: DemoRuntime

    var body: some View {
        ProjectsView(syncContainer: runtime.syncContainer, syncEngine: runtime.syncEngine)
        .toolbar {
            if !runtime.isUITesting {
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
}
