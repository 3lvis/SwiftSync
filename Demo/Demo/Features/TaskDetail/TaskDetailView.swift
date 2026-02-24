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
            sortBy: [\.sortOrder, \.id],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        List {
            taskSection
            peopleSection
            descriptionSection
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
            presentedSheet(for: sheet)
        }
    }

    private var actionMenu: some View {
        Menu {
            Button("Edit Description") { activeSheet = .description }
                .disabled(taskModel == nil)
            Button("Change Assignee") { activeSheet = .assignee }
                .disabled(taskModel == nil)
            Button("Change Reviewer") { activeSheet = .reviewer }
                .disabled(taskModel == nil)
            Button("Edit Watchers") { activeSheet = .watchers }
                .disabled(taskModel == nil)
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }

    private var taskSection: some View {
        Section("Task") {
            if let taskModel {
                Text(taskModel.title)
                    .font(.title3)
                HStack {
                    Text("State")
                    Spacer()
                    taskStateMenu(taskModel: taskModel)
                }
                HStack {
                    Text("Assignee")
                    Spacer()
                    Button {
                        activeSheet = .assignee
                    } label: {
                        Text(taskModel.assignee?.displayName ?? "Unassigned")
                            .foregroundStyle(Color.accentColor)
                    }
                }
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
            Button("Edit Description") {
                activeSheet = .description
            }
            .disabled(taskModel == nil)
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        if let taskModel {
            Section("People") {
                Button("Change Reviewer") {
                    activeSheet = .reviewer
                }
                Button("Edit Watchers") {
                    activeSheet = .watchers
                }

                if let author = taskModel.author {
                    NavigationLink {
                        UserTaskBucketsView(
                            userID: author.id,
                            syncContainer: syncContainer,
                            syncEngine: syncEngine
                        )
                    } label: {
                        LabeledContent("Author") {
                            Text(author.displayName)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } else {
                    LabeledContent("Author") {
                        Text("Unknown")
                            .foregroundStyle(.secondary)
                    }
                }

                if let assignee = taskModel.assignee {
                    NavigationLink {
                        UserTaskBucketsView(
                            userID: assignee.id,
                            syncContainer: syncContainer,
                            syncEngine: syncEngine
                        )
                    } label: {
                        LabeledContent("Assignee Tasks") {
                            Text(assignee.displayName)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                if let reviewer = taskModel.reviewer {
                    NavigationLink {
                        UserTaskBucketsView(
                            userID: reviewer.id,
                            syncContainer: syncContainer,
                            syncEngine: syncEngine
                        )
                    } label: {
                        LabeledContent("Reviewer Tasks") {
                            Text(reviewer.displayName)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } else {
                    LabeledContent("Reviewer") {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }

                if taskModel.watchers.isEmpty {
                    LabeledContent("Watchers") {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sortedWatchers(taskModel.watchers), id: \.id) { watcher in
                        NavigationLink {
                            UserTaskBucketsView(
                                userID: watcher.id,
                                syncContainer: syncContainer,
                                syncEngine: syncEngine
                            )
                        } label: {
                            LabeledContent("Watcher") {
                                Text(watcher.displayName)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }

    private func taskStateMenu(taskModel: Task) -> some View {
        let projectID = taskModel.projectID
        return Menu {
            if taskStateOptions.isEmpty {
                Button("Reload State Options") {
                    _Concurrency.Task {
                        await syncEngine.syncTaskStates()
                    }
                }
            } else {
                ForEach(taskStateOptions, id: \.id) { option in
                    Button {
                        _Concurrency.Task {
                            try? await syncEngine.updateTaskState(
                                taskID: taskID,
                                projectID: projectID,
                                state: option.id
                            )
                        }
                    } label: {
                        if taskModel.state == option.id {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
        } label: {
            Text(taskModel.stateLabel)
                .foregroundStyle(Color.accentColor)
        }
    }

    private func sortedWatchers(_ watchers: [User]) -> [User] {
        watchers.sorted {
            let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if nameOrder == .orderedSame {
                return $0.id < $1.id
            }
            return nameOrder == .orderedAscending
        }
    }

    @ViewBuilder
    private func presentedSheet(for sheet: TaskDetailSheet) -> some View {
        switch sheet {
        case .description:
            EditTaskDescriptionSheet(
                taskID: taskID,
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        case .assignee:
            AssigneePickerSheet(
                taskID: taskID,
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        case .reviewer:
            ReviewerPickerSheet(
                taskID: taskID,
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        case .watchers:
            EditTaskWatchersSheet(
                taskID: taskID,
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        }
    }
}


private struct UserTaskBucketsView: View {
    let userID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var userModel: User?
    @SyncQuery private var assignedTasks: [Task]
    @SyncQuery private var reviewTasks: [Task]
    @SyncQuery private var authoredTasks: [Task]
    @SyncQuery private var watchedTasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(userID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.userID = userID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _userModel = SyncModel(User.self, id: userID, in: syncContainer, animation: .snappy(duration: 0.22))
        _assignedTasks = SyncQuery(
            Task.self,
            relatedTo: User.self,
            relatedID: userID,
            through: \Task.assignee,
            in: syncContainer,
            sortBy: [\.title, \.id],
            refreshOn: [\.assignee],
            animation: .snappy(duration: 0.22)
        )
        _reviewTasks = SyncQuery(
            Task.self,
            relatedTo: User.self,
            relatedID: userID,
            through: \Task.reviewer,
            in: syncContainer,
            sortBy: [\.title, \.id],
            refreshOn: [\.reviewer],
            animation: .snappy(duration: 0.22)
        )
        _authoredTasks = SyncQuery(
            Task.self,
            relatedTo: User.self,
            relatedID: userID,
            through: \Task.author,
            in: syncContainer,
            sortBy: [\.title, \.id],
            refreshOn: [\.author],
            animation: .snappy(duration: 0.22)
        )
        _watchedTasks = SyncQuery(
            Task.self,
            relatedTo: User.self,
            relatedID: userID,
            through: \Task.watchers,
            in: syncContainer,
            sortBy: [\.title, \.id],
            refreshOn: [\.watchers],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        List {
            Section("User") {
                if let userModel {
                    LabeledContent("Name", value: userModel.displayName)
                    LabeledContent("Role", value: userModel.roleLabel)
                } else {
                    Text("User not found")
                        .foregroundStyle(.secondary)
                }
            }

            taskBucketSection("Assigned", tasks: assignedTasks)
            taskBucketSection("Reviewer", tasks: reviewTasks)
            taskBucketSection("Author", tasks: authoredTasks)
            taskBucketSection("Watcher", tasks: watchedTasks)
        }
        .navigationTitle(userModel?.displayName ?? "User")
        .refreshable {
            await syncEngine.syncUsers()
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncUsers()
        }
    }

    @ViewBuilder
    private func taskBucketSection(_ title: String, tasks: [Task]) -> some View {
        Section(title) {
            if tasks.isEmpty {
                Text("No tasks")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks, id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(taskID: task.id, syncContainer: syncContainer, syncEngine: syncEngine)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                            Text(task.stateLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
    case reviewer
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
            sortBy: [\.displayName, \.id],
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

private struct ReviewerPickerSheet: View {
    let taskID: String
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @SyncModel private var taskModel: Task?
    @SyncQuery private var users: [User]
    @State private var pendingReviewerID: String?
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
            sortBy: [\.displayName, \.id],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    pendingReviewerID = nil
                } label: {
                    HStack {
                        Text("None")
                        Spacer()
                        if pendingReviewerID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                ForEach(users, id: \.id) { user in
                    Button {
                        pendingReviewerID = user.id
                    } label: {
                        HStack {
                            Text(user.displayName)
                            Spacer()
                            if pendingReviewerID == user.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reviewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        let selection = pendingReviewerID
                        let projectID = taskModel?.projectID
                        isSaving = true
                        saveErrorMessage = nil
                        _Concurrency.Task {
                            do {
                                try await syncEngine.updateTaskReviewer(
                                    taskID: taskID,
                                    projectID: projectID,
                                    reviewerID: selection
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
            pendingReviewerID = taskModel.reviewerID
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
            sortBy: [\.displayName, \.id],
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
