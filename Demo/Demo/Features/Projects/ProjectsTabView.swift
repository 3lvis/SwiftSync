import SwiftData
import SwiftSync
import SwiftUI
import UIKit

struct ProjectsTabView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine
    @State private var selectedProjectID: String?

    var body: some View {
        NavigationStack {
            _ProjectsRepresentable(syncContainer: syncContainer, syncEngine: syncEngine) { projectID in
                selectedProjectID = projectID
            }
            .navigationTitle("Projects")
            .navigationDestination(item: $selectedProjectID) { projectID in
                ProjectDetailView(
                    projectID: projectID,
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
    }
}

private struct _ProjectsRepresentable: UIViewControllerRepresentable {
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine
    let onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> ProjectsViewController {
        ProjectsViewController(syncContainer: syncContainer, syncEngine: syncEngine, onSelect: onSelect)
    }

    func updateUIViewController(_ uiViewController: ProjectsViewController, context: Context) {}
}

// MARK: - Project Detail

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
                syncEngine: syncEngine
            )
        }
        .alert(
            "Delete Task?",
            isPresented: Binding(
                get: { taskPendingDelete != nil },
                set: { if !$0 { taskPendingDelete = nil } }
            ),
            presenting: taskPendingDelete
        ) { prompt in
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await syncEngine.deleteTask(taskID: prompt.id, projectID: projectID)
                    taskPendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { taskPendingDelete = nil }
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

    @Environment(\.dismiss) private var dismiss
    @SyncQuery private var users: [User]
    @SyncQuery private var taskStateOptions: [TaskStateOption]

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var stateID: String?
    @State private var assigneeID: String? = nil
    @State private var authorID: String? = nil
    @State private var isLoadingTaskStates = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = projectID
        self.syncEngine = syncEngine
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)],
            animation: .snappy(duration: 0.22)
        )
        _taskStateOptions = SyncQuery(
            TaskStateOption.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)

                    if taskStateOptions.isEmpty {
                        LabeledContent("State") {
                            if isLoadingTaskStates {
                                ProgressView()
                            } else {
                                Text("Unavailable")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !isLoadingTaskStates {
                            Button("Retry Loading States") { loadTaskStates() }
                        }
                    } else {
                        Picker("State", selection: $stateID) {
                            ForEach(taskStateOptions, id: \.id) { option in
                                Text(option.label).tag(Optional(option.id))
                            }
                        }
                    }

                    Picker("Assignee", selection: $assigneeID) {
                        Text("Unassigned").tag(String?.none)
                        ForEach(users, id: \.id) { user in
                            Text(user.displayName).tag(Optional(user.id))
                        }
                    }

                    Picker("Author", selection: $authorID) {
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
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        HStack(spacing: 6) {
                            if isSaving { ProgressView().controlSize(.small) }
                            Text("Create")
                        }
                    }
                    .disabled(
                        isSaving ||
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        stateID == nil ||
                        authorID == nil
                    )
                }
            }
        }
        .task { loadTaskStates() }
        .task(id: taskStateOptions.map(\.id)) {
            if let stateID, taskStateOptions.contains(where: { $0.id == stateID }) { return }
            self.stateID = taskStateOptions.first?.id
        }
        .task(id: users.map(\.id)) {
            if let authorID, users.contains(where: { $0.id == authorID }) { return }
            authorID = assigneeID.flatMap { id in
                users.contains(where: { $0.id == id }) ? id : nil
            } ?? users.first?.id
        }
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .presentationDetents([.medium, .large])
    }

    private func loadTaskStates() {
        guard !isLoadingTaskStates else { return }
        isLoadingTaskStates = true
        _Concurrency.Task {
            await syncEngine.syncTaskStates()
            await MainActor.run { isLoadingTaskStates = false }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let stateID, let authorID else { return }
        isSaving = true
        saveErrorMessage = nil
        _Concurrency.Task {
            do {
                try await syncEngine.createTask(
                    projectID: projectID,
                    title: trimmedTitle,
                    descriptionText: trimmedDescription.isEmpty ? "No description yet." : trimmedDescription,
                    state: stateID,
                    assigneeID: assigneeID,
                    authorID: authorID
                )
                await MainActor.run { isSaving = false; dismiss() }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { isSaving = false; saveErrorMessage = message }
            }
        }
    }
}
