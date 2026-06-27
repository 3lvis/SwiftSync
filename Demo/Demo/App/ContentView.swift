import DemoCore
import Observation
import SwiftSync
import SwiftUI

struct ContentView: View {
    @Bindable var runtime: DemoRuntime
    @State private var showingFailures = false

    private var engine: DemoSyncEngine { runtime.syncEngine }

    var body: some View {
        ProjectsView(syncEngine: runtime.syncEngine)
            // A safe-area inset, not a `.bottomBar` toolbar: the toolbar would attach outside
            // ProjectsView's own NavigationStack and drop out on re-render. This stays put.
            .safeAreaInset(edge: .bottom) { offlineBar }
            .toolbar {
                // The scenario picker is dev chrome with non-deterministic network behavior, so it
                // stays hidden under UI testing. The offline bar above is a real feature (and tested).
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
            .sheet(isPresented: $showingFailures) {
                FailuresSheet(syncEngine: engine)
            }
    }

    private var offlineBar: some View {
        HStack {
            Button {
                engine.isOffline.toggle()
            } label: {
                Label(
                    engine.isOffline ? "Offline" : "Online",
                    systemImage: engine.isOffline ? "wifi.slash" : "wifi"
                )
            }
            .tint(engine.isOffline ? .orange : .accentColor)
            .accessibilityIdentifier("offline-toggle")

            Spacer()

            if engine.pendingChangeCount > 0 {
                Text("\(engine.pendingChangeCount) pending")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pending-count")
            }

            if engine.failedChangeCount > 0 {
                if engine.pendingChangeCount > 0 { Spacer().frame(width: 12) }
                Button {
                    showingFailures = true
                } label: {
                    Label("\(engine.failedChangeCount) failed", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                }
                .tint(.red)
                .accessibilityIdentifier("failures-button")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
