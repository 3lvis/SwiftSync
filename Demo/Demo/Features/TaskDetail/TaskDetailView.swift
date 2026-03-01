import SwiftData
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var taskModel: Task?
    @SyncQuery private var taskStateOptions: [TaskStateOption]
    @State private var hasTriggeredInitialSync = false
    @State private var showingEditSheet = false

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
        _taskStateOptions = SyncQuery(
            TaskStateOption.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        List {
            taskSection
            descriptionSection
            peopleSection
        }
        .navigationTitle("Task")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
                .disabled(taskModel == nil)
            }
        }
        .refreshable {
            await syncEngine.syncTaskStates()
            await syncEngine.syncTaskDetail(taskID: taskID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncTaskStates()
            await syncEngine.syncTaskDetail(taskID: taskID)
        }
        .task(id: taskID) {
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(nanoseconds: 14_000_000_000)
                guard !_Concurrency.Task.isCancelled else { break }
                guard !showingEditSheet else { continue }
                await syncEngine.syncTaskDetail(taskID: taskID)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let taskModel {
                EditTaskSheet(
                    taskModel: taskModel,
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
    }

    private var taskSection: some View {
        Section {
            if let taskModel {
                VStack(alignment: .leading, spacing: 12) {
                    Text(taskModel.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    HStack(spacing: 8) {
                        Text(taskModel.stateLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        Text(taskModel.author?.displayName ?? "Unknown")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Task not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            Text(taskModel?.descriptionText ?? "")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        if let taskModel {
            Section("Assignee") {
                Text(taskModel.assignee?.displayName ?? "Unassigned")
                    .foregroundStyle(taskModel.assignee == nil ? .secondary : .primary)
            }

            Section("Reviewers") {
                if taskModel.reviewers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(taskModel.reviewers.sorted { $0.displayName < $1.displayName }, id: \.id) { reviewer in
                        Text(reviewer.displayName)
                    }
                }
            }

            Section("Watchers") {
                if taskModel.watchers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(
                        taskModel.watchers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
                        id: \.id
                    ) { watcher in
                        Text(watcher.displayName)
                    }
                }
            }
        }
    }
}

// MARK: - Edit Task Sheet

private struct EditTaskSheet: View {
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    // The original IDs for change detection on relationships
    private let originalReviewerIDs: Set<String>
    private let originalWatcherIDs: Set<String>
    private let taskID: String
    private let projectID: String

    @Environment(\.dismiss) private var dismiss

    // Live queries for pickers
    @SyncQuery private var taskStateOptions: [TaskStateOption]
    @SyncQuery private var users: [User]

    // Draft — uninserted copy of the task's scalar fields
    @State private var draftTitle: String
    @State private var draftDescription: String
    @State private var draftStateID: String
    @State private var draftStateLabel: String
    @State private var draftAssigneeID: String?

    // Relationship sets
    @State private var reviewerIDs: Set<String>
    @State private var watcherIDs: Set<String>

    // Save state
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(taskModel: Task, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        self.taskID = taskModel.id
        self.projectID = taskModel.projectID

        let initialReviewerIDs = Set(taskModel.reviewers.map(\.id))
        let initialWatcherIDs = Set(taskModel.watchers.map(\.id))
        self.originalReviewerIDs = initialReviewerIDs
        self.originalWatcherIDs = initialWatcherIDs

        _taskStateOptions = SyncQuery(
            TaskStateOption.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)]
        )
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)]
        )

        _draftTitle = State(initialValue: taskModel.title)
        _draftDescription = State(initialValue: taskModel.descriptionText)
        _draftStateID = State(initialValue: taskModel.state)
        _draftStateLabel = State(initialValue: taskModel.stateLabel)
        _draftAssigneeID = State(initialValue: taskModel.assigneeID)
        _reviewerIDs = State(initialValue: initialReviewerIDs)
        _watcherIDs = State(initialValue: initialWatcherIDs)
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                descriptionSection
                stateSection
                assigneeSection
                reviewersSection
                watchersSection
            }
            .navigationTitle("Edit Task")
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
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
    }

    // MARK: Form sections

    private var titleSection: some View {
        Section("Title") {
            TextEditor(text: $draftTitle)
                .frame(minHeight: 60)
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            TextEditor(text: $draftDescription)
                .frame(minHeight: 120)
        }
    }

    private var stateSection: some View {
        Section("State") {
            ForEach(taskStateOptions, id: \.id) { option in
                Button {
                    draftStateID = option.id
                    draftStateLabel = option.label
                } label: {
                    HStack {
                        Text(option.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if draftStateID == option.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var assigneeSection: some View {
        Section("Assignee") {
            Button {
                draftAssigneeID = nil
            } label: {
                HStack {
                    Text("Unassigned")
                        .foregroundStyle(.primary)
                    Spacer()
                    if draftAssigneeID == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            ForEach(users, id: \.id) { user in
                Button {
                    draftAssigneeID = user.id
                } label: {
                    HStack {
                        Text(user.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if draftAssigneeID == user.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
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
                        Text(user.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if reviewerIDs.contains(user.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
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
                        Text(user.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if watcherIDs.contains(user.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: Save

    private func save() {
        isSaving = true
        saveErrorMessage = nil

        let body: [String: Any] = [
            "title": draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": draftDescription,
            "state": ["id": draftStateID, "label": draftStateLabel] as [String: Any],
            "assignee_id": draftAssigneeID ?? NSNull()
        ]

        let reviewersChanged = reviewerIDs != originalReviewerIDs
        let watchersChanged = watcherIDs != originalWatcherIDs
        let capturedReviewerIDs = reviewerIDs.sorted()
        let capturedWatcherIDs = watcherIDs.sorted()

        _Concurrency.Task {
            do {
                try await syncEngine.updateTask(taskID: taskID, projectID: projectID, body: body)

                if reviewersChanged {
                    try await syncEngine.replaceTaskReviewers(
                        taskID: taskID,
                        projectID: projectID,
                        reviewerIDs: capturedReviewerIDs
                    )
                }

                if watchersChanged {
                    try await syncEngine.replaceTaskWatchers(
                        taskID: taskID,
                        projectID: projectID,
                        watcherIDs: capturedWatcherIDs
                    )
                }

                await MainActor.run { dismiss() }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    isSaving = false
                    saveErrorMessage = message
                }
            }
        }
    }
}
