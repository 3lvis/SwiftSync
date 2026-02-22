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
            sortBy: [\.name, \.id]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects, id: \.id) { project in
                    NavigationLink {
                        ProjectDetailView(
                            project: project,
                            syncContainer: syncContainer,
                            syncEngine: syncEngine
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.headline)
                            Text(project.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
        }
    }
}

private struct ProjectDetailView: View {
    let projectID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var projectModel: Project?
    @SyncQuery private var tasks: [Task]
    @SyncQuery private var users: [User]
    @State private var hasTriggeredInitialSync = false
    @State private var isShowingCreateTaskSheet = false
    @State private var taskPendingDelete: TaskDeletePrompt?

    init(project: Project, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = project.id
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _projectModel = SyncModel(Project.self, id: project.id, in: syncContainer)
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [\.displayName, \.id]
        )
        _tasks = SyncQuery(
            Task.self,
            toOne: project,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.id)
            ],
            refreshOn: [\.assignee]
        )
    }

    var body: some View {
        List {
            Section {
                if let projectModel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(projectModel.name)
                            .font(.title3)
                        Text("Status: \(projectModel.status)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Project not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tasks") {
                ForEach(tasks, id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(task: task, syncContainer: syncContainer, syncEngine: syncEngine)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.headline)
                            Text(task.state)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let assignee = task.assignee?.displayName {
                                Text("Assignee: \(assignee)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        .navigationTitle(projectModel?.name ?? "Project")
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
        .sheet(isPresented: $isShowingCreateTaskSheet) {
            CreateTaskSheet(
                users: users,
                defaultAssigneeID: nil
            ) { title, descriptionText, state, assigneeID in
                await syncEngine.createTask(
                    projectID: projectID,
                    title: title,
                    descriptionText: descriptionText,
                    state: state,
                    assigneeID: assigneeID,
                    tagIDs: []
                )
            }
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
    let users: [User]
    let defaultAssigneeID: String?
    let onCreate: (_ title: String, _ descriptionText: String, _ state: String, _ assigneeID: String?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var state = DemoTaskStateOption.todo
    @State private var assigneeID: String?
    @State private var isSaving = false

    init(
        users: [User],
        defaultAssigneeID: String?,
        onCreate: @escaping (_ title: String, _ descriptionText: String, _ state: String, _ assigneeID: String?) async -> Void
    ) {
        self.users = users
        self.defaultAssigneeID = defaultAssigneeID
        self.onCreate = onCreate
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
                    Button("Create") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty else { return }

                        isSaving = true
                        _Concurrency.Task {
                            await onCreate(
                                trimmedTitle,
                                trimmedDescription.isEmpty ? "No description yet." : trimmedDescription,
                                state.rawValue,
                                assigneeID
                            )
                            await MainActor.run {
                                isSaving = false
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
