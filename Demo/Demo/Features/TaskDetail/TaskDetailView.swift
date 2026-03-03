import SwiftData
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var taskModel: Task?
    @SyncQuery private var taskStateOptions: [TaskStateOption]
    @State private var hasTriggeredInitialSync = false
    @State private var showingEditSheet = false

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
        _taskStateOptions = SyncQuery(
            TaskStateOption.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        List {
            taskSection
            descriptionSection
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
        .refreshable {
            await syncEngine.syncTaskStates()
            await syncEngine.syncTaskDetail(taskID: taskID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncTaskStates()
            await syncEngine.syncTaskDetail(taskID: taskID)
        }
        .task(id: taskID) {
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(nanoseconds: 14_000_000_000)
                guard !_Concurrency.Task.isCancelled else { break }
                guard !showingEditSheet else { continue }
                await syncEngine.syncTaskDetail(taskID: taskID)
            }
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
}

