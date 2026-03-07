import SwiftData
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var taskModel: Task?
    @State private var hasTriggeredInitialSync = false
    @State private var showingEditSheet = false
#if DEBUG
    @State private var showingStressPrompt = false
#endif

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
    }

    var body: some View {
        List {
            taskSection
            descriptionSection
            itemsSection
            peopleSection
        }
        .navigationTitle("Task")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
                .disabled(taskModel == nil)
            }
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.loadTaskDetailScreen(taskID: taskID)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let taskModel {
                TaskFormSheet(
                    mode: .edit(task: taskModel),
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
#if DEBUG
        .overlay(alignment: .bottom) {
            if syncEngine.isEarthquakeModeRunning,
               let status = syncEngine.earthquakeStatusText {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                    Text(status)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Stop") {
                        syncEngine.stopEarthquakeMode()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .alert("Stress test this screen?", isPresented: $showingStressPrompt) {
            Button("Start Stress", role: .destructive) {
                syncEngine.startEarthquakeMode(for: .taskDetail(taskID: taskID))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Debug-only Earthquake Mode runs finite add/edit/delete overlap for this task screen.")
        }
        .background(
            ShakeDetector {
                guard !syncEngine.isEarthquakeModeRunning else { return }
                guard !showingEditSheet else { return }
                showingStressPrompt = true
            }
            .allowsHitTesting(false)
        )
#endif
    }

    private var taskSection: some View {
        Section {
            if let taskModel {
                VStack(alignment: .leading, spacing: 12) {
                    Text(taskModel.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    HStack(spacing: 8) {
                        Text(taskModel.stateLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        Text(taskModel.author?.displayName ?? "Unknown")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Task not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            Text(taskModel?.descriptionText ?? "")
                .font(.body)
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        if let taskModel {
            Section("Items") {
                if taskModel.items.isEmpty {
                    Text("No items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedItems(for: taskModel), id: \.id) { item in
                        Text(item.title)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        if let taskModel {
            Section("Assignee") {
                Text(taskModel.assignee?.displayName ?? "Unassigned")
                    .foregroundStyle(taskModel.assignee == nil ? .secondary : .primary)
            }

            Section("Reviewers") {
                if taskModel.reviewers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(taskModel.reviewers.sorted { $0.displayName < $1.displayName }, id: \.id) { reviewer in
                        Text(reviewer.displayName)
                    }
                }
            }

            Section("Watchers") {
                if taskModel.watchers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(
                        taskModel.watchers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
                        id: \.id
                    ) { watcher in
                        Text(watcher.displayName)
                    }
                }
            }
        }
    }

    private func sortedItems(for task: Task) -> [Item] {
        task.items.sorted {
            if $0.position == $1.position {
                return $0.id < $1.id
            }
            return $0.position < $1.position
        }
    }
}
