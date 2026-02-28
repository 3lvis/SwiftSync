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
    @State private var activeSheet: TaskDetailSheet?

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
                actionMenu
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
                guard activeSheet == nil else { continue }
                await syncEngine.syncTaskDetail(taskID: taskID)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .description:
                EditTaskDescriptionSheet(taskID: taskID, syncContainer: syncContainer, syncEngine: syncEngine)
            case .assignee:
                AssigneePickerSheet(taskID: taskID, syncContainer: syncContainer, syncEngine: syncEngine)
            case .reviewers:
                EditTaskReviewersSheet(taskID: taskID, syncContainer: syncContainer, syncEngine: syncEngine)
            case .watchers:
                EditTaskWatchersSheet(taskID: taskID, syncContainer: syncContainer, syncEngine: syncEngine)
            }
        }
    }

    private var actionMenu: some View {
        Menu {
            Button("Edit Description") { activeSheet = .description }
                .disabled(taskModel == nil)
            Menu("Change State") {
                ForEach(taskStateOptions, id: \.id) { option in
                    Button {
                        _Concurrency.Task {
                            try? await syncEngine.updateTaskState(
                                taskID: taskID,
                                projectID: taskModel?.projectID,
                                state: option.id
                            )
                        }
                    } label: {
                        if taskModel?.state == option.id {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
            .disabled(taskModel == nil)
            Button("Change Assignee") { activeSheet = .assignee }
                .disabled(taskModel == nil)
            Button("Edit Reviewers") { activeSheet = .reviewers }
                .disabled(taskModel == nil)
            Button("Edit Watchers") { activeSheet = .watchers }
                .disabled(taskModel == nil)
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
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
            Section("People") {
                LabeledContent("Assignee") {
                    Text(taskModel.assignee?.displayName ?? "Unassigned")
                        .foregroundStyle(.secondary)
                }

                if taskModel.reviewers.isEmpty {
                    LabeledContent("Reviewers") {
                        Text("None").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(taskModel.reviewers.sorted { $0.displayName < $1.displayName }, id: \.id) { reviewer in
                        LabeledContent("Reviewer") {
                            Text(reviewer.displayName).foregroundStyle(.secondary)
                        }
                    }
                }

                if taskModel.watchers.isEmpty {
                    LabeledContent("Watchers") {
                        Text("None").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(
                        taskModel.watchers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
                        id: \.id
                    ) { watcher in
                        LabeledContent("Watcher") {
                            Text(watcher.displayName).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

}


private enum TaskDetailSheet: String, Identifiable {
    case description
    case assignee
    case reviewers
    case watchers

    var id: String { rawValue }
}

private struct EditTaskDescriptionSheet: View {
    let taskID: String
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @SyncModel private var taskModel: Task?
    @State private var text = ""
    @State private var hasLoadedInitialValue = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncEngine = syncEngine
        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                }
            }
            .navigationTitle("Edit Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        isSaving = true
                        saveErrorMessage = nil
                        _Concurrency.Task {
                            do {
                                try await syncEngine.updateTaskDescription(
                                    taskID: taskID,
                                    projectID: taskModel?.projectID,
                                    descriptionText: trimmed
                                )
                                await MainActor.run {
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
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task(id: taskModel?.id) {
            guard !hasLoadedInitialValue, let taskModel else { return }
            text = taskModel.descriptionText
            hasLoadedInitialValue = true
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

private struct AssigneePickerSheet: View {
    let taskID: String
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @SyncModel private var taskModel: Task?
    @SyncQuery private var users: [User]
    @State private var pendingAssigneeID: String?
    @State private var hasLoadedInitialValue = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncEngine = syncEngine
        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    pendingAssigneeID = nil
                } label: {
                    HStack {
                        Text("Unassigned")
                        Spacer()
                            if pendingAssigneeID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                }

                ForEach(users, id: \.id) { user in
                    Button {
                        pendingAssigneeID = user.id
                    } label: {
                        HStack {
                            Text(user.displayName)
                            Spacer()
                            if pendingAssigneeID == user.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Assignee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        let selection = pendingAssigneeID
                        let projectID = taskModel?.projectID
                        isSaving = true
                        saveErrorMessage = nil
                        _Concurrency.Task {
                            do {
                                try await syncEngine.updateTaskAssignee(
                                    taskID: taskID,
                                    projectID: projectID,
                                    assigneeID: selection
                                )
                                await MainActor.run {
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
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task(id: taskModel?.id) {
            guard !hasLoadedInitialValue, let taskModel else { return }
            pendingAssigneeID = taskModel.assigneeID
            hasLoadedInitialValue = true
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

private struct EditTaskReviewersSheet: View {
    let taskID: String
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @SyncModel private var taskModel: Task?
    @SyncQuery private var users: [User]
    @State private var pendingReviewerIDs: Set<String> = []
    @State private var hasLoadedInitialSelection = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncEngine = syncEngine
        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(users, id: \.id) { user in
                    Button {
                        if pendingReviewerIDs.contains(user.id) {
                            pendingReviewerIDs.remove(user.id)
                        } else {
                            pendingReviewerIDs.insert(user.id)
                        }
                    } label: {
                        HStack {
                            Text(user.displayName)
                            Spacer()
                            if pendingReviewerIDs.contains(user.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reviewers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        isSaving = true
                        saveErrorMessage = nil
                        let reviewerIDs = pendingReviewerIDs.sorted()
                        _Concurrency.Task {
                            do {
                                try await syncEngine.replaceTaskReviewers(
                                    taskID: taskID,
                                    projectID: taskModel?.projectID,
                                    reviewerIDs: reviewerIDs
                                )
                                await MainActor.run {
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
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task(id: taskModel?.reviewers.map(\.id).sorted() ?? []) {
            guard !hasLoadedInitialSelection, let taskModel else { return }
            pendingReviewerIDs = Set(taskModel.reviewers.map(\.id))
            hasLoadedInitialSelection = true
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

private struct EditTaskWatchersSheet: View {
    let taskID: String
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @SyncModel private var taskModel: Task?
    @SyncQuery private var users: [User]
    @State private var pendingWatcherIDs: Set<String> = []
    @State private var hasLoadedInitialSelection = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncEngine = syncEngine
        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(users, id: \.id) { user in
                    Button {
                        if pendingWatcherIDs.contains(user.id) {
                            pendingWatcherIDs.remove(user.id)
                        } else {
                            pendingWatcherIDs.insert(user.id)
                        }
                    } label: {
                        HStack {
                            Text(user.displayName)
                            Spacer()
                            if pendingWatcherIDs.contains(user.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Watchers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        isSaving = true
                        saveErrorMessage = nil
                        let watcherIDs = pendingWatcherIDs.sorted()
                        _Concurrency.Task {
                            do {
                                try await syncEngine.replaceTaskWatchers(
                                    taskID: taskID,
                                    projectID: taskModel?.projectID,
                                    watcherIDs: watcherIDs
                                )
                                await MainActor.run {
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
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task(id: taskModel?.watchers.map(\.id).sorted() ?? []) {
            guard !hasLoadedInitialSelection, let taskModel else { return }
            pendingWatcherIDs = Set(taskModel.watchers.map(\.id))
            hasLoadedInitialSelection = true
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
