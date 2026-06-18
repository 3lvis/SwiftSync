import DemoCore
import Observation
import SwiftSync
import SwiftUI

struct ContentView: View {
    @Bindable var runtime: DemoRuntime
    @State private var syncResult: SyncResultAlert?

    private var engine: DemoSyncEngine { runtime.syncEngine }

    var body: some View {
        ProjectsView(syncContainer: runtime.syncContainer, syncEngine: runtime.syncEngine)
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
            .alert(item: $syncResult) { result in
                Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
            }
            // Reconnecting drains the offline queue automatically (silently — the manual "Sync now"
            // button is for explicit/retry pushes and keeps its result alert).
            .onChange(of: engine.isOffline) { _, isNowOffline in
                if !isNowOffline && engine.pendingChangeCount > 0 {
                    autoSync()
                }
            }
    }

    private func autoSync() {
        _Concurrency.Task { try? await engine.pushPendingChanges() }
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

            Spacer()

            Button("Sync now", action: pushPendingChanges)
                .disabled(engine.isOffline || engine.pendingChangeCount == 0 || engine.isSyncing)
                .accessibilityIdentifier("sync-now")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func pushPendingChanges() {
        _Concurrency.Task {
            do {
                guard let summary = try await engine.pushPendingChanges() else { return }
                syncResult = SyncResultAlert(summary: summary)
            } catch {
                syncResult = SyncResultAlert(title: "Sync failed", message: error.localizedDescription)
            }
        }
    }
}

private struct SyncResultAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(summary: SyncPushSummary) {
        let applied = summary.insertedCount + summary.updatedCount + summary.deletedCount
        if summary.failures.isEmpty {
            title = "Synced"
            message = "Pushed \(applied) change\(applied == 1 ? "" : "s") to the server."
        } else {
            title = "Synced with \(summary.failures.count) failure\(summary.failures.count == 1 ? "" : "s")"
            let lines = summary.failures.map { "• \($0.operation.rawValue): \($0.message)" }
            message = (["Pushed \(applied) change\(applied == 1 ? "" : "s")."] + lines).joined(separator: "\n")
        }
    }
}
