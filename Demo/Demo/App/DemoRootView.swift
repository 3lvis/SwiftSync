import SwiftUI
import SwiftSync

struct DemoRootView: View {
    @ObservedObject var runtime: DemoRuntime

    var body: some View {
        TabView {
            ProjectsTabView(syncContainer: runtime.syncContainer, syncEngine: runtime.syncEngine)
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }

            UsersTabView(syncContainer: runtime.syncContainer, syncEngine: runtime.syncEngine)
                .tabItem {
                    Label("Users", systemImage: "person.2")
                }
        }
        .task {
            await runtime.bootstrapIfNeeded()
        }
        .safeAreaInset(edge: .bottom) {
            if let error = runtime.syncEngine.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.12))
            }
        }
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
