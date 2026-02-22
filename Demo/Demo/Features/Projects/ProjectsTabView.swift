import SwiftData
import SwiftSync
import SwiftUI

struct ProjectsTabView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncQuery private var projects: [Project]
    @State private var hasTriggeredInitialSync = false

    init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        _projects = SyncQuery(
            Project.self,
            in: syncContainer,
            sortBy: [\.name, \.id],
            animation: .snappy(duration: 0.24)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects, id: \.id) { project in
                    NavigationLink(value: project.id) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(project.name)
                                .font(.headline)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                Text(project.status)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text(project.taskCount == 1 ? "1 task" : "\(project.taskCount) tasks")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if projects.isEmpty && syncEngine.isSyncing {
                    ProgressView("Syncing projects...")
                }
            }
            .navigationTitle("Projects")
            .refreshable {
                await syncEngine.syncProjects()
                await syncEngine.syncTags()
            }
            .task {
                guard !hasTriggeredInitialSync else { return }
                hasTriggeredInitialSync = true
                await syncEngine.syncProjects()
                await syncEngine.syncTags()
            }
            .navigationDestination(for: String.self) { projectID in
                ProjectDetailView(
                    projectID: projectID,
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
    }
}

private struct ProjectDetailView: View {
    let projectID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var projectModel: Project?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false
    @State private var isShowingCreateTaskSheet = false
    @State private var taskPendingDelete: TaskDeletePrompt?

    init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = projectID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _projectModel = SyncModel(Project.self, id: projectID, in: syncContainer)
        _tasks = SyncQuery(
            Task.self,
            relatedTo: Project.self,
            relatedID: projectID,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.id)
            ],
            refreshOn: [\.assignee],
            animation: .snappy(duration: 0.24)
        )
    }

    var body: some View {
        List {
            Section {
                if let projectModel {
                    Text(projectModel.name)
                        .font(.headline)
                        .lineLimit(3)

                    LabeledContent("Status", value: projectModel.status)
                        .foregroundStyle(.secondary)

                    LabeledContent("Tasks", value: projectModel.taskCount == 1 ? "1 task" : "\(projectModel.taskCount) tasks")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Project not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tasks") {
                ForEach(tasks, id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(taskID: task.id, syncContainer: syncContainer, syncEngine: syncEngine)
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
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            taskPendingDelete = TaskDeletePrompt(id: task.id, title: task.title)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCreateTaskSheet = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
        .refreshable {
            await syncEngine.syncProjectTasks(projectID: projectID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncProjectTasks(projectID: projectID)
        }
        .task(id: projectID) {
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000_000)
                guard !_Concurrency.Task.isCancelled else { break }
                await syncEngine.syncProjectTasks(projectID: projectID)
            }
        }
        .sheet(isPresented: $isShowingCreateTaskSheet) {
            CreateTaskSheet(
                projectID: projectID,
                syncContainer: syncContainer,
                syncEngine: syncEngine,
                defaultAssigneeID: nil
            )
        }
        .alert(
            "Delete Task?",
            isPresented: Binding(
                get: { taskPendingDelete != nil },
                set: { isPresented in
                    if !isPresented { taskPendingDelete = nil }
                }
            ),
            presenting: taskPendingDelete
        ) { prompt in
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await syncEngine.deleteTask(taskID: prompt.id, projectID: projectID)
                    taskPendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                taskPendingDelete = nil
            }
        } message: { prompt in
            Text("Delete \"\(prompt.title)\" from this project?")
        }
    }
}

private struct TaskDeletePrompt: Equatable {
    let id: String
    let title: String
}

private struct CreateTaskSheet: View {
    let projectID: String
    let syncEngine: DemoSyncEngine
    let defaultAssigneeID: String?

    @Environment(\.dismiss) private var dismiss
    @SyncQuery private var users: [User]

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var state = DemoTaskStateOption.todo
    @State private var assigneeID: String?
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(
        projectID: String,
        syncContainer: SyncContainer,
        syncEngine: DemoSyncEngine,
        defaultAssigneeID: String?,
    ) {
        self.projectID = projectID
        self.syncEngine = syncEngine
        self.defaultAssigneeID = defaultAssigneeID
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [\.displayName, \.id],
            animation: .snappy(duration: 0.22)
        )
        _assigneeID = State(initialValue: defaultAssigneeID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)

                    Picker("State", selection: $state) {
                        ForEach(DemoTaskStateOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    Picker("Assignee", selection: $assigneeID) {
                        Text("Unassigned").tag(String?.none)
                        ForEach(users, id: \.id) { user in
                            Text(user.displayName).tag(Optional(user.id))
                        }
                    }
                }

                Section("Description") {
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty else { return }

                        isSaving = true
                        saveErrorMessage = nil
                        _Concurrency.Task {
                            do {
                                try await syncEngine.createTask(
                                    projectID: projectID,
                                    title: trimmedTitle,
                                    descriptionText: trimmedDescription.isEmpty ? "No description yet." : trimmedDescription,
                                    state: state.rawValue,
                                    assigneeID: assigneeID,
                                    tagIDs: []
                                )
                                await MainActor.run {
                                    isSaving = false
                                    dismiss()
                                }
                            } catch {
                                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                await MainActor.run {
                                    isSaving = false
                                    saveErrorMessage = message
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Create")
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { saveErrorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .presentationDetents([.medium, .large])
    }
}

private enum DemoTaskStateOption: String, CaseIterable, Identifiable {
    case todo
    case inProgress
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo:
            return "To Do"
        case .inProgress:
            return "In Progress"
        case .done:
            return "Done"
        }
    }
}
