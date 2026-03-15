import DemoCore
import SwiftSync
import SwiftUI

struct TaskView: View {
    let taskID: String
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    @State private var machine: TaskViewMachine
    @State private var showingEditSheet = false

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _machine = State(
            initialValue: TaskViewMachine(taskID: taskID, syncContainer: syncContainer, syncEngine: syncEngine)
        )
    }

    var body: some View {
        List { content }
            .accessibilityIdentifier("task.detail")
            .listStyle(.plain)
            .listSectionSpacing(.compact)
            .navigationTitle("Task")
            .toolbar { toolbarContent }
            .task(loadTask)
            .animation(.snappy(duration: 0.2), value: itemIDs)
            .animation(.snappy(duration: 0.2), value: reviewerIDs)
            .animation(.snappy(duration: 0.2), value: watcherIDs)
            .sheet(isPresented: $showingEditSheet) { editTaskSheet }
    }
}

extension TaskView {
    var task: Task? {
        machine.task
    }

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
            peopleSection
            itemsSection
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
            .accessibilityIdentifier("task.edit")
            .disabled(task == nil)
        }
    }

    @ViewBuilder
    var editTaskSheet: some View {
        if let taskModel = task {
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
        task?.reviewers.map(\.id).sorted() ?? []
    }

    var watcherIDs: [String] {
        task?.watchers.map(\.id).sorted() ?? []
    }

    @ViewBuilder
    func errorSection(_ presentation: ErrorPresentationState) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    var taskSection: some View {
        Section {
            if let taskModel = task {
                VStack(alignment: .leading, spacing: 8) {
                    Text(taskModel.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .accessibilityIdentifier("task.title")
                    Text((taskModel.descriptionText?.isEmpty == false) ? (taskModel.descriptionText ?? "") : "No description yet.")
                        .font(.body)
                        .foregroundStyle((taskModel.descriptionText?.isEmpty == false) ? .primary : .secondary)
                        .accessibilityIdentifier("task.description")
                    HStack(spacing: 6) {
                        Text(taskModel.stateLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        personChip(
                            role: "Author",
                            name: taskModel.author?.displayName ?? "Unknown",
                            identifier: "task.author"
                        )
                        personChip(
                            role: "Assignee",
                            name: taskModel.assignee?.displayName ?? "Unassigned",
                            identifier: "task.assignee"
                        )
                    }
                }
            } else {
                Text("Task details unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var itemsSection: some View {
        if task != nil {
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
        if let taskModel = task {
            Section("Reviewers") {
                if taskModel.reviewers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(taskModel.reviewers.sorted(by: { $0.displayName < $1.displayName }), id: \.id) { reviewer in
                        Text(reviewer.displayName)
                            .accessibilityIdentifier("task.reviewer.\(reviewer.id)")
                    }
                }
            }

            Section("Watchers") {
                if taskModel.watchers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(taskModel.watchers.sorted(by: { $0.displayName < $1.displayName }), id: \.id) { watcher in
                        Text(watcher.displayName)
                            .accessibilityIdentifier("task.watcher.\(watcher.id)")
                    }
                }
            }
        }
    }

    @Sendable
    func loadTask() async {
        machine.send(.onAppear)
    }

    func personChip(role: String, name: String, identifier: String) -> some View {
        HStack(spacing: 4) {
            Text(role)
                .foregroundStyle(.secondary)
            Text(name)
                .foregroundStyle(.primary)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(name)
    }
}
