import SwiftUI
import SwiftSync

struct DemoRootView: View {
    @ObservedObject var runtime: DemoRuntime
    @State private var isShowingEngineStatus = false

    var body: some View {
        ProjectsTabView(syncContainer: runtime.syncContainer, syncEngine: runtime.syncEngine)
        .task {
            await runtime.bootstrapIfNeeded()
        }
        .overlay(alignment: .bottom) {
            if isShowingEngineStatus {
                EngineStatusOverlayView(syncEngine: runtime.syncEngine) {
                    isShowingEngineStatus = false
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(
            ShakeDetector {
                isShowingEngineStatus.toggle()
            }
            .allowsHitTesting(false)
        )
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
