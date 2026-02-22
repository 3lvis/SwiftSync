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
                        ProjectListRow(
                            name: project.name,
                            status: project.status,
                            taskCount: project.taskCount
                        )
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
                ProjectDetailView(
                    projectID: projectID,
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
    }
}

private struct ProjectListRow: View {
    let name: String
    let status: String
    let taskCount: Int

    private var taskCountLabel: String {
        taskCount == 1 ? "1 task" : "\(taskCount) tasks"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(status)
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
    @State private var hasTriggeredInitialSync = false
    @State private var isShowingCreateTaskSheet = false
    @State private var taskPendingDelete: TaskDeletePrompt?
    @State private var selectedTaskRoute: ProjectDetailTaskRoute?

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
                    ProjectDetailHeaderCard(
                        name: projectModel.name,
                        status: projectModel.status,
                        taskCount: projectModel.taskCount
                    )
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
                        ProjectTaskListRow(
                            title: task.title,
                            state: task.state,
                            assigneeName: task.assignee?.displayName
                        )
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
                try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000_000)
                guard !_Concurrency.Task.isCancelled else { break }
                await syncEngine.syncProjectTasks(projectID: projectID)
            }
        }
        .navigationDestination(item: $selectedTaskRoute) { route in
            TaskDetailView(taskID: route.id, syncContainer: syncContainer, syncEngine: syncEngine)
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

private struct ProjectDetailTaskRoute: Identifiable, Hashable {
    let id: String
}

private struct ProjectDetailHeaderCard: View {
    let name: String
    let status: String
    let taskCount: Int

    private var taskCountLabel: String {
        taskCount == 1 ? "1 task" : "\(taskCount) tasks"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name)
                .font(.title2.weight(.semibold))
                .lineLimit(3)

            HStack(spacing: 10) {
                Text(status)
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
    let title: String
    let state: String
    let assigneeName: String?

    private var stateLabel: String {
        switch state {
        case "todo":
            return "To do"
        case "inProgress":
            return "In progress"
        case "done":
            return "Done"
        default:
            return state
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
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

                    if let assignee = assigneeName {
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
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
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
