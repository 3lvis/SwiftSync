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

    @StateObject private var metadataLoadMachine: ScreenLoadMachine
    @StateObject private var saveMachine: SubmissionMachine
    @State private var newItemTitle = ""
    @State private var itemEditMode: EditMode = .inactive

    init(mode: TaskFormMode, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.mode = mode
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        let ctx = ModelContext(syncContainer.modelContainer)
        ctx.autosaveEnabled = false
        self.editContext = ctx
        _metadataLoadMachine = StateObject(
            wrappedValue: ScreenLoadMachine { error in
                presentError(
                    error,
                    retryActionTitle: "Retry Loading Metadata",
                    fallbackMessage: "Could not load form options yet."
                )
            }
        )
        _saveMachine = StateObject(
            wrappedValue: SubmissionMachine { error in
                presentError(
                    error,
                    retryActionTitle: nil,
                    fallbackMessage: "Could not save this task."
                )
            }
        )

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
                loadErrorSection
                titleSection
                descriptionSection
                itemsSection
                stateSection
                assigneeSection
                if case .create = mode { authorSection }
                reviewersSection
                watchersSection
            }
            .environment(\.editMode, $itemEditMode)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(saveMachine.state == .submitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.descriptionText = "No description yet."
                        }
                        normalizeItemPositions()
                        draft.updatedAt = Date()
                        guard saveMachine.send(.submit) else { return }

                        let body = draft.exportObject(for: syncContainer)
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
                                await MainActor.run {
                                    _ = saveMachine.send(.success)
                                    dismiss()
                                }
                            } catch {
                                await MainActor.run {
                                    _ = saveMachine.send(.failure(error))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if saveMachine.state == .submitting { ProgressView().controlSize(.small) }
                            Text(confirmLabel)
                        }
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .task {
            refreshSnapshot()
            requestLoad(.onAppear)
        }
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
                get: {
                    if case .failed = saveMachine.state { return true }
                    return false
                },
                set: { isPresented in
                    if !isPresented {
                        _ = saveMachine.send(.dismissError)
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let error) = saveMachine.state {
                Text(error.message)
            } else {
                Text("Unknown error")
            }
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

    private var itemsSection: some View {
        Section("Items") {
            HStack(spacing: 8) {
                TextField("Add item...", text: $newItemTitle)
                    .textInputAutocapitalization(.sentences)

                Button("Add") {
                    addItem()
                }
                .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if sortedItems.count > 1 {
                Button(itemEditMode == .active ? "Done Reordering" : "Reorder Items") {
                    withAnimation(.snappy(duration: 0.2)) {
                        itemEditMode = itemEditMode == .active ? .inactive : .active
                    }
                }
            }

            if sortedItems.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedItems, id: \.id) { item in
                    HStack(spacing: 10) {
                        TextField("Item title", text: itemTitleBinding(for: item))

                        Spacer(minLength: 4)

                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove(perform: moveItems)
            }
        }
    }

    private var stateSection: some View {
        Section("State") {
            if taskStateOptions.isEmpty {
                LabeledContent("State") {
                    if metadataLoadMachine.state.isLoading {
                        ProgressView()
                    } else {
                        Text("Unavailable").foregroundStyle(.secondary)
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

    @ViewBuilder
    private var loadErrorSection: some View {
        if let metadataError = metadataLoadMachine.state.errorPresentation {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(metadataError.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let retryActionTitle = metadataError.retryActionTitle {
                        Button(retryActionTitle) {
                            requestLoad(.retry)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
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
        guard saveMachine.state != .submitting,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return true }
        if case .create = mode {
            return draft.state.isEmpty || draft.authorID.isEmpty
        }
        return false
    }

    private static func metadataSnapshot(from context: ModelContext) -> (users: [User], taskStateOptions: [TaskStateOption]) {
        let userDescriptor = FetchDescriptor<User>(
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)]
        )
        let users = (try? context.fetch(userDescriptor)) ?? []

        let stateDescriptor = FetchDescriptor<TaskStateOption>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)]
        )
        let taskStateOptions = (try? context.fetch(stateDescriptor)) ?? []

        return (users, taskStateOptions)
    }

    @MainActor
    private func requestLoad(_ event: ScreenLoadEvent) {
        metadataLoadMachine.send(event, run: {
            try await syncEngine.syncTaskFormMetadata()
            await MainActor.run {
                refreshSnapshot()
            }
        })
    }

    @MainActor
    private func refreshSnapshot() {
        let snapshot = Self.metadataSnapshot(from: editContext)
        users = snapshot.users
        taskStateOptions = snapshot.taskStateOptions
    }

    private var sortedItems: [Item] {
        draft.items.sorted {
            if $0.position == $1.position {
                return $0.id < $1.id
            }
            return $0.position < $1.position
        }
    }

    private func itemTitleBinding(for item: Item) -> Binding<String> {
        Binding(
            get: { item.title },
            set: { newValue in
                item.title = newValue
                item.updatedAt = Date()
            }
        )
    }

    private func addItem() {
        let trimmed = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = Item(
            title: trimmed,
            position: draft.items.count,
            createdAt: Date(),
            updatedAt: Date(),
            task: draft
        )
        draft.items.append(item)
        normalizeItemPositions()
        newItemTitle = ""
    }

    private func deleteItem(_ item: Item) {
        draft.items.removeAll { $0.id == item.id }
        editContext.delete(item)
        normalizeItemPositions()
    }

    private func normalizeItemPositions() {
        for (index, item) in sortedItems.enumerated() {
            item.position = index
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var reordered = sortedItems
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.position = index
            item.updatedAt = Date()
        }
    }
}
