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

    // Throwaway context — autosave disabled. Never saved to the store.
    // On cancel it is simply released; on save we export the values and call the API.
    private let editContext: ModelContext

    // The draft lives in editContext. For create it is a freshly-inserted Task.
    // For edit it is the same row fetched into this isolated context.
    // Relationship arrays (reviewers, watchers) are real [User] objects from editContext,
    // so the pickers can assign them directly without cross-context crashes.
    @State private var draft: Task

    // Loaded once from editContext when the sheet appears. Not kept live — form sheets
    // are short-lived and a stale list for one session is acceptable.
    @State private var users: [User] = []
    @State private var taskStateOptions: [TaskStateOption] = []

    @State private var isLoadingTaskStates = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(mode: TaskFormMode, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.mode = mode
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        let ctx = ModelContext(syncContainer.modelContainer)
        ctx.autosaveEnabled = false
        self.editContext = ctx

        switch mode {
        case .create(let projectID):
            let task = Task(projectID: projectID)
            ctx.insert(task)
            _draft = State(initialValue: task)

        case .edit(let task):
            let taskID = task.id
            let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID })
            let fetched = (try? ctx.fetch(descriptor))?.first
            // Fallback should never be reached in practice — the row is always in the store.
            // If it somehow is, we fall back to the passed object (which lives in mainContext,
            // so edits won't reach the store either, preserving the no-save guarantee).
            _draft = State(initialValue: fetched ?? task)
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
        .task { loadData() }
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
                    if draft.reviewers.contains(where: { $0.id == user.id }) {
                        draft.reviewers.removeAll(where: { $0.id == user.id })
                    } else {
                        draft.reviewers.append(user)
                    }
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if draft.reviewers.contains(where: { $0.id == user.id }) {
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
                    if draft.watchers.contains(where: { $0.id == user.id }) {
                        draft.watchers.removeAll(where: { $0.id == user.id })
                    } else {
                        draft.watchers.append(user)
                    }
                } label: {
                    HStack {
                        Text(user.displayName).foregroundStyle(.primary)
                        Spacer()
                        if draft.watchers.contains(where: { $0.id == user.id }) {
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

    private func loadData() {
        users = syncEngine.localUsers()
        taskStateOptions = syncEngine.localTaskStates()

        _Concurrency.Task {
            await syncEngine.loadTaskFormScreen()
            await MainActor.run {
                users = syncEngine.localUsers()
                taskStateOptions = syncEngine.localTaskStates()
            }
        }
    }

    private func loadTaskStates() {
        guard !isLoadingTaskStates else { return }
        isLoadingTaskStates = true
        _Concurrency.Task {
            await syncEngine.refreshTaskFormScreen()
            let descriptor = FetchDescriptor<TaskStateOption>(
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)]
            )
            let options = (try? editContext.fetch(descriptor)) ?? []
            await MainActor.run {
                taskStateOptions = options
                isLoadingTaskStates = false
            }
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

        // Derive original relationship membership from the mode enum — no stored state needed.
        // We still dirty-check to avoid unnecessary PUT /reviewers and PUT /watchers calls,
        // which are costly (mutation latency + flaky-network failure risk).
        let capturedReviewerIDs = draft.reviewers.map(\.id).sorted()
        let capturedWatcherIDs = draft.watchers.map(\.id).sorted()

        var reviewersChanged = false
        var watchersChanged = false
        if case .edit(let originalTask) = mode {
            let originalReviewerIDs = Set(originalTask.reviewers.map(\.id))
            let originalWatcherIDs = Set(originalTask.watchers.map(\.id))
            reviewersChanged = Set(capturedReviewerIDs) != originalReviewerIDs
            watchersChanged = Set(capturedWatcherIDs) != originalWatcherIDs
        }

        _Concurrency.Task {
            do {
                switch mode {
                case .create(let projectID):
                    try await syncEngine.createTask(body: body, projectID: projectID)
                    // On create, always send if non-empty — there is no prior state to diff against.
                    if !capturedReviewerIDs.isEmpty {
                        try await syncEngine.replaceTaskReviewers(
                            taskID: draft.id,
                            projectID: projectID,
                            reviewerIDs: capturedReviewerIDs
                        )
                    }
                    if !capturedWatcherIDs.isEmpty {
                        try await syncEngine.replaceTaskWatchers(
                            taskID: draft.id,
                            projectID: projectID,
                            watcherIDs: capturedWatcherIDs
                        )
                    }

                case .edit(let task):
                    try await syncEngine.updateTask(taskID: task.id, projectID: task.projectID, body: body)
                    if reviewersChanged {
                        try await syncEngine.replaceTaskReviewers(
                            taskID: task.id,
                            projectID: task.projectID,
                            reviewerIDs: capturedReviewerIDs
                        )
                    }
                    if watchersChanged {
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
