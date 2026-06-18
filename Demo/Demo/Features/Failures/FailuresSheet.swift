import DemoCore
import SwiftData
import SwiftSync
import SwiftUI

/// The failures inbox: rows the server rejected (a `syncFailureReason` is set). The user resolves each
/// by editing the task (fix → re-syncs) or discarding the change (restores the server's version).
/// Driven by the engine's observable `failedChangeCount` so it refreshes as failures clear.
struct FailuresSheet: View {
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Task] = []
    @State private var editingTask: Task?

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView("No failures", systemImage: "checkmark.circle")
                } else {
                    ForEach(rows, id: \.id) { task in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.title).font(.headline)
                            if let kind = task.syncFailureKind.flatMap(SyncFailureKind.init(rawValue:)) {
                                Text(badgeLabel(kind))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(badgeColor(kind), in: Capsule())
                                    .accessibilityIdentifier("failure.kind.\(task.id)")
                            }
                            if let reason = task.syncFailureReason {
                                Label(reason, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            HStack {
                                Button("Edit") { editingTask = task }
                                    .accessibilityIdentifier("failure.edit.\(task.id)")
                                Spacer()
                                Button("Discard", role: .destructive) { discard(task) }
                                    .accessibilityIdentifier("failure.discard.\(task.id)")
                            }
                            .buttonStyle(.borderless)
                            .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Failed to sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .accessibilityIdentifier("failures-sheet")
            .sheet(item: $editingTask) { task in
                TaskFormSheet(mode: .edit(task: task), syncContainer: syncContainer, syncEngine: syncEngine)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: syncEngine.failedChangeCount) { _, _ in reload() }
    }

    private func reload() {
        rows = syncEngine.failedTasks()
    }

    private func discard(_ task: Task) {
        let taskID = task.id
        _Concurrency.Task {
            try? await syncEngine.discardFailedChange(taskID: taskID)
            reload()
        }
    }

    private func badgeLabel(_ kind: SyncFailureKind) -> String {
        switch kind {
        case .validation: return "Needs a fix"
        case .server, .transport: return "Temporary"
        case .conflict: return "Conflict"
        }
    }

    private func badgeColor(_ kind: SyncFailureKind) -> Color {
        // Validation is the user's to fix (prominent); a retryable one is transient (calmer).
        kind.isRetryable ? Color(.systemGray) : .orange
    }
}
