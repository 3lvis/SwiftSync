import SwiftData
import SwiftSync
import SwiftUI

enum TaskFormMode {
    case create(projectID: String)
    case edit(task: Task)
}

private struct TaskDraft {
    var id: String
    var projectID: String
    var title: String
    var descriptionText: String
    var state: String
    var stateLabel: String
    var assigneeID: String?
    var authorID: String
    var reviewerIDs: Set<String>
    var watcherIDs: Set<String>
    var createdAt: Date
    var updatedAt: Date

    init(projectID: String) {
        let now = Date()
        id = UUID().uuidString
        self.projectID = projectID
        title = ""
        descriptionText = ""
        state = ""
        stateLabel = ""
        assigneeID = nil
        authorID = ""
        reviewerIDs = []
        watcherIDs = []
        createdAt = now
        updatedAt = now
    }

    init(task: Task) {
        id = task.id
        projectID = task.projectID
        title = task.title
        descriptionText = task.descriptionText
        state = task.state
        stateLabel = task.stateLabel
        assigneeID = task.assigneeID
        authorID = task.authorID
        reviewerIDs = Set(task.reviewers.map(\.id))
        watcherIDs = Set(task.watchers.map(\.id))
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }
}

struct TaskFormSheet: View {
    let mode: TaskFormMode
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskDraft
    @State private var users: [User] = []
    @State private var taskStateOptions: [TaskStateOption] = []

    @State private var isLoadingTaskStates = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(mode: TaskFormMode, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.mode = mode
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        switch mode {
        case .create(let projectID):
            _draft = State(initialValue: TaskDraft(projectID: projectID))
        case .edit(let task):
            _draft = State(initialValue: TaskDraft(task: task))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                descriptionSection
                stateSection
                assigneeSection
                if case .create = mode { authorSection }
                reviewersSection
                watchersSection
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving { ProgressView().controlSize(.small) }
                            Text(confirmLabel)
                        }
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .task { await reloadMetadata() }
        .task(id: taskStateOptions.map(\.id)) {
            guard !taskStateOptions.isEmpty,
                  draft.state.isEmpty || !taskStateOptions.contains(where: { $0.id == draft.state })
            else { return }
            if let first = taskStateOptions.first {
                draft.state = first.id
                draft.stateLabel = first.label
            }
        }
        .task(id: users.map(\.id)) {
            guard !users.isEmpty,
                  draft.authorID.isEmpty || !users.contains(where: { $0.id == draft.authorID })
            else { return }
            draft.authorID = draft.assigneeID.flatMap { id in
                users.contains(where: { $0.id == id }) ? id : nil
            } ?? users.first?.id ?? ""
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
        .presentationDetents([.large])
    }

    private var titleSection: some View {
        Section("Title") {
            TextEditor(text: $draft.title)
                .frame(minHeight: 60)
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            TextEditor(text: $draft.descriptionText)
                .frame(minHeight: 120)
        }
    }

    private var stateSection: some View {
        Section("State") {
            if taskStateOptions.isEmpty {
                LabeledContent("State") {
                    if isLoadingTaskStates {
                        ProgressView()
                    } else {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                }
                if !isLoadingTaskStates {
                    Button("Retry Loading States") {
                        _Concurrency.Task { await reloadMetadata() }
                    }
                }
            } else {
                ForEach(taskStateOptions, id: \.id) { option in
                    Button {
                        draft.state = option.id
                        draft.stateLabel = option.label
                    } label: {
                        HStack {
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            if draft.state == option.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }

    private var assigneeSection: some View {
        Section("Assignee") {
            Button {
                draft.assigneeID = nil
            } label: {
                HStack {
                    Text("Unassigned").foregroundStyle(.primary)
                    Spacer()
                    if draft.assigneeID == nil {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
            ForEach(users, id: \.id) { user in
                Button {
                    draft.assigneeID = user.id
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if draft.assigneeID == user.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var authorSection: some View {
        Section("Author") {
            ForEach(users, id: \.id) { user in
                Button {
                    draft.authorID = user.id
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if draft.authorID == user.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var reviewersSection: some View {
        Section("Reviewers") {
            ForEach(users, id: \.id) { user in
                Button {
                    if draft.reviewerIDs.contains(user.id) {
                        draft.reviewerIDs.remove(user.id)
                    } else {
                        draft.reviewerIDs.insert(user.id)
                    }
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if draft.reviewerIDs.contains(user.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var watchersSection: some View {
        Section("Watchers") {
            ForEach(users, id: \.id) { user in
                Button {
                    if draft.watcherIDs.contains(user.id) {
                        draft.watcherIDs.remove(user.id)
                    } else {
                        draft.watcherIDs.insert(user.id)
                    }
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if draft.watcherIDs.contains(user.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: "New Task"
        case .edit: "Edit Task"
        }
    }

    private var confirmLabel: String {
        switch mode {
        case .create: "Create"
        case .edit: "Save"
        }
    }

    private var isSaveDisabled: Bool {
        guard !isSaving,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return true }
        if case .create = mode {
            return draft.state.isEmpty || draft.authorID.isEmpty
        }
        return false
    }

    @MainActor
    private func reloadMetadata() async {
        let local = Self.metadataSnapshot(context: syncContainer.mainContext)
        users = local.users
        taskStateOptions = local.taskStateOptions

        guard !isLoadingTaskStates else { return }
        isLoadingTaskStates = true
        defer { isLoadingTaskStates = false }

        await syncEngine.loadTaskFormScreen()

        let refreshed = Self.metadataSnapshot(context: syncContainer.mainContext)
        users = refreshed.users
        taskStateOptions = refreshed.taskStateOptions
    }

    @MainActor
    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.descriptionText = "No description yet."
        }
        draft.updatedAt = Date()
        isSaving = true
        saveErrorMessage = nil

        let reviewerIDs = draft.reviewerIDs.sorted()
        let watcherIDs = draft.watcherIDs.sorted()

        let originalReviewerIDs: Set<String>
        let originalWatcherIDs: Set<String>
        if case .edit(let task) = mode {
            originalReviewerIDs = Set(task.reviewers.map(\.id))
            originalWatcherIDs = Set(task.watchers.map(\.id))
        } else {
            originalReviewerIDs = []
            originalWatcherIDs = []
        }

        let reviewersChanged = Set(reviewerIDs) != originalReviewerIDs
        let watchersChanged = Set(watcherIDs) != originalWatcherIDs

        let body = makeTaskPayload(draft: draft)

        _Concurrency.Task {
            do {
                switch mode {
                case .create(let projectID):
                    try await syncEngine.createTask(body: body, projectID: projectID)
                    if !reviewerIDs.isEmpty {
                        try await syncEngine.replaceTaskReviewers(taskID: draft.id, projectID: projectID, reviewerIDs: reviewerIDs)
                    }
                    if !watcherIDs.isEmpty {
                        try await syncEngine.replaceTaskWatchers(taskID: draft.id, projectID: projectID, watcherIDs: watcherIDs)
                    }

                case .edit(let task):
                    try await syncEngine.updateTask(taskID: task.id, projectID: task.projectID, body: body)
                    if reviewersChanged {
                        try await syncEngine.replaceTaskReviewers(taskID: task.id, projectID: task.projectID, reviewerIDs: reviewerIDs)
                    }
                    if watchersChanged {
                        try await syncEngine.replaceTaskWatchers(taskID: task.id, projectID: task.projectID, watcherIDs: watcherIDs)
                    }
                }

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
    }

    private func makeTaskPayload(draft: TaskDraft) -> [String: Any] {
        let stateLabel = taskStateOptions.first(where: { $0.id == draft.state })?.label ?? draft.stateLabel
        let formatter = ISO8601DateFormatter()

        return [
            "id": draft.id,
            "project_id": draft.projectID,
            "assignee_id": draft.assigneeID ?? NSNull(),
            "author_id": draft.authorID,
            "title": draft.title,
            "description": draft.descriptionText,
            "state": ["id": draft.state, "label": stateLabel],
            "created_at": formatter.string(from: draft.createdAt),
            "updated_at": formatter.string(from: draft.updatedAt)
        ]
    }

    private static func metadataSnapshot(context: ModelContext) -> (users: [User], taskStateOptions: [TaskStateOption]) {
        let users = (try? context.fetch(FetchDescriptor<User>(sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)]))) ?? []
        let taskStateOptions = (try? context.fetch(FetchDescriptor<TaskStateOption>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)]))) ?? []
        return (users, taskStateOptions)
    }
}
