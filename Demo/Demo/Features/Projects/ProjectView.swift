import DemoCore
import SwiftSync
import SwiftUI

struct ProjectView: View {
    let projectID: String
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    @State private var machine: ProjectViewMachine
    @State private var isShowingCreateTaskSheet = false
    @State private var taskPendingDelete: TaskDeletePrompt?

    init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = projectID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _machine = State(
            initialValue: ProjectViewMachine(projectID: projectID, syncContainer: syncContainer, syncEngine: syncEngine)
        )
    }

    var body: some View {
        List { content }
        .listStyle(.plain)
        .accessibilityIdentifier("project.detail")
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(loadProject)
        .animation(.snappy(duration: 0.2), value: taskIDs)
        .projectPresentations(
            createTaskSheetIsPresented: $isShowingCreateTaskSheet,
            createTaskSheet: { createTaskSheet },
            deletePromptIsPresented: deletePromptIsPresented,
            taskPendingDelete: taskPendingDelete,
            onConfirmDelete: confirmDelete,
            onCancelDelete: { taskPendingDelete = nil },
            deleteFailureIsPresented: deleteFailureIsPresented,
            deleteFailureMessage: deleteFailureMessage,
            onDismissDeleteFailure: { machine.sendDelete(.dismissError) }
        )
    }

    private var taskIDs: [String] {
        machine.tasks.map(\.id)
    }

    @ViewBuilder
    private var content: some View {
        if let presentation = machine.loadErrorPresentation {
            errorSection(presentation)
        }

        switch machine.contentState {
        case .loading:
            Section {
                LabeledContent("Status") {
                    ProgressView("Loading project...")
                }
            }
        case .content:
            projectSection
            tasksSection
        case .notFound:
            Section {
                Text("Project not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isShowingCreateTaskSheet = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .accessibilityIdentifier("project.new-task")
        }
    }

    private var createTaskSheet: some View {
        TaskFormSheet(
            mode: .create(projectID: projectID),
            syncContainer: syncContainer,
            syncEngine: syncEngine
        )
    }

    private var deletePromptIsPresented: Binding<Bool> {
        Binding(
            get: { taskPendingDelete != nil },
            set: { if !$0 { taskPendingDelete = nil } }
        )
    }

    private var deleteFailureIsPresented: Binding<Bool> {
        Binding(
            get: {
                if case .failed = machine.deleteState { return true }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    machine.sendDelete(.dismissError)
                }
            }
        )
    }

    private var deleteFailureMessage: String {
        if case .failed(let presentation) = machine.deleteState {
            return presentation.message
        }
        return "Could not delete this task."
    }

    private func loadProject() {
        machine.send(.onAppear)
    }

    private func confirmDelete(_ prompt: TaskDeletePrompt) {
        machine.sendDelete(.request(taskID: prompt.id))
        taskPendingDelete = nil
    }

    @ViewBuilder
    private func errorSection(_ presentation: ErrorPresentationState) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(presentation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var projectSection: some View {
        Section {
            if let projectModel = machine.project {
                Text(projectModel.name)
                    .font(.headline)
                    .lineLimit(3)

                LabeledContent("Tasks", value: projectModel.taskCount == 1 ? "1 task" : "\(projectModel.taskCount) tasks")
                    .foregroundStyle(.secondary)
            } else {
                Text("Project details unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tasksSection: some View {
        Section("Tasks") {
            if machine.tasks.isEmpty {
                Text("No tasks yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(machine.tasks, id: \.id) { task in
                    NavigationLink {
                        TaskView(taskID: task.id, syncContainer: syncContainer, syncEngine: syncEngine)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(.headline)
                                .lineLimit(3)

                            HStack(spacing: 8) {
                                Text(task.stateLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if let assignee = task.assignee?.displayName {
                                    Text("Assignee: \(assignee)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                if !task.items.isEmpty {
                                    Text("\(task.items.count) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("project.task.\(task.id)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            taskPendingDelete = TaskDeletePrompt(id: task.id, title: task.title)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        }
    }
}

private struct TaskDeletePrompt: Equatable {
    let id: String
    let title: String
}

private extension View {
    func projectPresentations<SheetContent: View>(
        createTaskSheetIsPresented: Binding<Bool>,
        @ViewBuilder createTaskSheet: @escaping () -> SheetContent,
        deletePromptIsPresented: Binding<Bool>,
        taskPendingDelete: TaskDeletePrompt?,
        onConfirmDelete: @escaping (TaskDeletePrompt) -> Void,
        onCancelDelete: @escaping () -> Void,
        deleteFailureIsPresented: Binding<Bool>,
        deleteFailureMessage: String,
        onDismissDeleteFailure: @escaping () -> Void
    ) -> some View {
        self
            .sheet(isPresented: createTaskSheetIsPresented) {
                createTaskSheet()
            }
            .alert("Delete Task?", isPresented: deletePromptIsPresented, presenting: taskPendingDelete) { prompt in
                Button("Delete", role: .destructive) { onConfirmDelete(prompt) }
                Button("Cancel", role: .cancel) { onCancelDelete() }
            } message: { prompt in
                Text("Delete \"\(prompt.title)\" from this project?")
            }
            .alert("Delete Failed", isPresented: deleteFailureIsPresented) {
                Button("OK", role: .cancel) { onDismissDeleteFailure() }
            } message: {
                Text(deleteFailureMessage)
            }
    }
}
