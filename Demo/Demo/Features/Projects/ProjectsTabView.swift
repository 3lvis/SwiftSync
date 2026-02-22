import SwiftData
import SwiftSync
import SwiftUI

struct ProjectsTabView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncQuery private var projects: [Project]
    @State private var hasTriggeredInitialSync = false
    @State private var navigationPath: [String] = []

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
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(projects, id: \.id) { project in
                    Button {
                        navigationPath.append(project.id)
                    } label: {
                        ProjectListRow(project: project)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
                if let project = projects.first(where: { $0.id == projectID }) {
                    ProjectDetailView(
                        project: project,
                        syncContainer: syncContainer,
                        syncEngine: syncEngine
                    )
                } else {
                    Text("Project not found")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ProjectListRow: View {
    let project: Project

    private var taskCountLabel: String {
        project.taskCount == 1 ? "1 task" : "\(project.taskCount) tasks"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(project.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 8) {
                Text(taskCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemFill))
                    )

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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
    @State private var selectedTaskRoute: ProjectDetailTaskRoute?

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
            refreshOn: [\.assignee],
            animation: .snappy(duration: 0.24)
        )
    }

    var body: some View {
        List {
            Section {
                if let projectModel {
                    ProjectDetailHeaderCard(project: projectModel)
                } else {
                    Text("Project not found")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section("Tasks") {
                ForEach(tasks, id: \.id) { task in
                    Button {
                        selectedTaskRoute = ProjectDetailTaskRoute(id: task.id)
                    } label: {
                        ProjectTaskListRow(task: task)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
                try? await _Concurrency.Task.sleep(nanoseconds: 4_500_000_000)
                guard !_Concurrency.Task.isCancelled else { break }
                await syncEngine.syncProjectTasks(projectID: projectID)
            }
        }
        .navigationDestination(item: $selectedTaskRoute) { route in
            if let task = tasks.first(where: { $0.id == route.id }) {
                TaskDetailView(task: task, syncContainer: syncContainer, syncEngine: syncEngine)
            } else {
                Text("Task not found")
                    .foregroundStyle(.secondary)
            }
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

private struct ProjectDetailTaskRoute: Identifiable, Hashable {
    let id: String
}

private struct ProjectDetailHeaderCard: View {
    let project: Project

    private var taskCountLabel: String {
        project.taskCount == 1 ? "1 task" : "\(project.taskCount) tasks"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project.name)
                .font(.title2.weight(.semibold))
                .lineLimit(3)

            HStack(spacing: 10) {
                Text(project.status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(taskCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemFill))
                    )

                Spacer(minLength: 0)
            }
        }
        .padding(16)
    }
}

private struct ProjectTaskListRow: View {
    let task: Task

    private var stateLabel: String {
        switch task.state {
        case "todo":
            return "To do"
        case "inProgress":
            return "In progress"
        case "done":
            return "Done"
        default:
            return task.state
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                HStack(alignment: .center, spacing: 8) {
                    Text(stateLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemFill))
                        )

                    if let assignee = task.assignee?.displayName {
                        Text("Assignee: \(assignee)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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
