import SwiftUI
import DemoCore
import SwiftSync

struct DemoRootView: View {
    @ObservedObject var runtime: DemoRuntime

    var body: some View {
        ProjectsTabView(syncContainer: runtime.syncContainer, syncEngine: runtime.syncEngine)
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
