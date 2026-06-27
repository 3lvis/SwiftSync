import DemoCore
import SwiftData
import SwiftSync
import SwiftUI

struct FailuresSheet: View {
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @State private var failures: SyncQueryPublisher<Task>
    @State private var editingTask: Task?

    init(syncEngine: DemoSyncEngine) {
        self.syncEngine = syncEngine
        _failures = State(
            initialValue: SyncQueryPublisher(
                Task.self,
                predicate: #Predicate { $0.syncFailureReason != nil },
                in: syncEngine.syncContainer,
                sortBy: [SortDescriptor(\Task.updatedAt, order: .reverse)]))
    }

    var body: some View {
        let rows = failures.rows
        return NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView("No failures", systemImage: "checkmark.circle")
                } else {
                    ForEach(rows, id: \.id) { task in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.title).font(.headline)
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
                TaskFormSheet(mode: .edit(task: task), syncEngine: syncEngine)
            }
        }
    }

    private func discard(_ task: Task) {
        let taskID = task.id
        _Concurrency.Task { try? await syncEngine.discardFailedChange(taskID: taskID) }
    }
}
