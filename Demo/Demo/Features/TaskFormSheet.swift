import SwiftData
import SwiftSync
import SwiftUI

// MARK: - Mode

enum TaskFormMode {
    case create(projectID: String)
    case edit(task: Task)
}

// MARK: - Sheet

struct TaskFormSheet: View {
    let mode: TaskFormMode
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss

    @SyncQuery private var users: [User]
    @SyncQuery private var taskStateOptions: [TaskStateOption]

    // Single uninserted draft Task — mutated freely, exported at save time.
    // For create: initialised with blank values.
    // For edit: initialised as a scalar copy of the existing task.
    @State private var draft: Task

    // Relationship membership — tracked separately because Task.reviewers / Task.watchers
    // are [User] relationship arrays that require a ModelContext to be meaningful.
    @State private var reviewerIDs: Set<String>
    @State private var watcherIDs: Set<String>
    private let originalReviewerIDs: Set<String>
    private let originalWatcherIDs: Set<String>

    @State private var isLoadingTaskStates = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(mode: TaskFormMode, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.mode = mode
        self.syncContainer = syncContainer
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

        switch mode {
        case .create(let projectID):
            let now = Date()
            _draft = State(initialValue: Task(
                id: UUID().uuidString,
                projectID: projectID,
                assigneeID: nil,
                authorID: "",
                title: "",
                descriptionText: "",
                state: "",
                stateLabel: "",
                createdAt: now,
                updatedAt: now
            ))
            _reviewerIDs = State(initialValue: [])
            _watcherIDs = State(initialValue: [])
            originalReviewerIDs = []
            originalWatcherIDs = []

        case .edit(let task):
            _draft = State(initialValue: Task(
                id: task.id,
                projectID: task.projectID,
                assigneeID: task.assigneeID,
                authorID: task.authorID,
                title: task.title,
                descriptionText: task.descriptionText,
                state: task.state,
                stateLabel: task.stateLabel,
                createdAt: task.createdAt,
                updatedAt: task.updatedAt
            ))
            let initialReviewerIDs = Set(task.reviewers.map(\.id))
            let initialWatcherIDs = Set(task.watchers.map(\.id))
            _reviewerIDs = State(initialValue: initialReviewerIDs)
            _watcherIDs = State(initialValue: initialWatcherIDs)
            originalReviewerIDs = initialReviewerIDs
            originalWatcherIDs = initialWatcherIDs
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                descriptionSection
                stateSection
                assigneeSection
                if case .create = mode { authorSection }
                if case .edit = mode { reviewersSection; watchersSection }
            }
            .navigationTitle(navigationTitle)
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
                            Text(confirmLabel)
                        }
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .task { loadTaskStates() }
        // Auto-select first valid state when options load (safe for edit — guard prevents override)
        .task(id: taskStateOptions.map(\.id)) {
            guard !taskStateOptions.isEmpty,
                  draft.state.isEmpty || !taskStateOptions.contains(where: { $0.id == draft.state })
            else { return }
            if let first = taskStateOptions.first {
                draft.state = first.id
                draft.stateLabel = first.label
            }
        }
        // Auto-select author when users load (create only in practice — guard prevents override)
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

    // MARK: Sections

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
                    Button("Retry Loading States") { loadTaskStates() }
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
                    if reviewerIDs.contains(user.id) {
                        reviewerIDs.remove(user.id)
                    } else {
                        reviewerIDs.insert(user.id)
                    }
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if reviewerIDs.contains(user.id) {
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
                    if watcherIDs.contains(user.id) {
                        watcherIDs.remove(user.id)
                    } else {
                        watcherIDs.insert(user.id)
                    }
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if watcherIDs.contains(user.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: Helpers

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

    // MARK: Actions

    private func loadTaskStates() {
        guard !isLoadingTaskStates else { return }
        isLoadingTaskStates = true
        _Concurrency.Task {
            await syncEngine.syncTaskStates()
            await MainActor.run { isLoadingTaskStates = false }
        }
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.descriptionText = "No description yet."
        }
        draft.updatedAt = Date()
        isSaving = true
        saveErrorMessage = nil

        let body = draft.exportObject(for: syncContainer, relationshipMode: .none)
        let capturedReviewerIDs = reviewerIDs.sorted()
        let capturedWatcherIDs = watcherIDs.sorted()

        _Concurrency.Task {
            do {
                switch mode {
                case .create(let projectID):
                    try await syncEngine.createTask(body: body, projectID: projectID)

                case .edit(let task):
                    try await syncEngine.updateTask(taskID: task.id, projectID: task.projectID, body: body)
                    if reviewerIDs != originalReviewerIDs {
                        try await syncEngine.replaceTaskReviewers(
                            taskID: task.id,
                            projectID: task.projectID,
                            reviewerIDs: capturedReviewerIDs
                        )
                    }
                    if watcherIDs != originalWatcherIDs {
                        try await syncEngine.replaceTaskWatchers(
                            taskID: task.id,
                            projectID: task.projectID,
                            watcherIDs: capturedWatcherIDs
                        )
                    }
                }
                await MainActor.run { isSaving = false; dismiss() }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { isSaving = false; saveErrorMessage = message }
            }
        }
    }
}
