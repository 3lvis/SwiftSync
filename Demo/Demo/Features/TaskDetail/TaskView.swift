import SwiftData
import DemoCore
import SwiftSync
import SwiftUI

struct TaskView: View {
    let taskID: String
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    @State private var machine: TaskDetailMachine
    @State private var showingEditSheet = false

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _machine = State(
            initialValue: TaskDetailMachine(taskID: taskID, syncContainer: syncContainer, syncEngine: syncEngine)
        )
    }

    var body: some View {
        List { content }
        .navigationTitle("Task")
        .toolbar { toolbarContent }
        .task { machine.send(.onAppear) }
        .animation(.snappy(duration: 0.2), value: itemIDs)
        .animation(.snappy(duration: 0.2), value: reviewerIDs)
        .animation(.snappy(duration: 0.2), value: watcherIDs)
        .sheet(isPresented: $showingEditSheet) { editTaskSheet }
    }
}

extension TaskView {
    @ViewBuilder
    var content: some View {
        if let presentation = machine.loadErrorPresentation {
            errorSection(presentation)
        }

        switch machine.contentState {
        case .loading:
            Section {
                LabeledContent("Status") {
                    ProgressView("Loading task...")
                }
            }
        case .content:
            taskSection
            descriptionSection
            itemsSection
            peopleSection
        case .notFound:
            Section {
                Text("Task not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") {
                showingEditSheet = true
            }
            .disabled(machine.task == nil)
        }
    }

    @ViewBuilder
    var editTaskSheet: some View {
        if let taskModel = machine.task {
            TaskFormSheet(
                mode: .edit(task: taskModel),
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        }
    }

    var itemIDs: [String] {
        machine.items.map(\.id)
    }

    var reviewerIDs: [String] {
        machine.task?.reviewers.map(\.id).sorted() ?? []
    }

    var watcherIDs: [String] {
        machine.task?.watchers.map(\.id).sorted() ?? []
    }

    @ViewBuilder
    func errorSection(_ presentation: ErrorPresentationState) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(presentation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    var taskSection: some View {
        Section {
            if let taskModel = machine.task {
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
                Text("Task details unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var descriptionSection: some View {
        if let taskModel = machine.task {
            Section("Description") {
                Text(taskModel.descriptionText)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    var itemsSection: some View {
        if machine.task != nil {
            Section("Items") {
                if machine.items.isEmpty {
                    Text("No items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(machine.items, id: \.id) { item in
                        Text(item.title)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var peopleSection: some View {
        if let taskModel = machine.task {
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
