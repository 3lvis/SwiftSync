import SwiftData
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var taskModel: Task?
    @SyncQuery private var tags: [Tag]
    @SyncQuery private var comments: [Comment]
    @SyncQuery private var allUsers: [User]
    @SyncQuery private var allTags: [Tag]
    @State private var hasTriggeredInitialSync = false
    @State private var activeSheet: TaskDetailSheet?
    @State private var commentPendingDelete: CommentDeletePrompt?

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
        _allUsers = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [\.displayName, \.id]
        )
        _allTags = SyncQuery(
            Tag.self,
            in: syncContainer,
            sortBy: [\.name, \.id]
        )
        _tags = SyncQuery(
            Tag.self,
            relatedTo: Task.self,
            relatedID: taskID,
            in: syncContainer,
            sortBy: [\.name, \.id],
            refreshOn: [\.tasks],
            animation: .snappy(duration: 0.22)
        )
        _comments = SyncQuery(
            Comment.self,
            relatedTo: Task.self,
            relatedID: taskID,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Comment.createdAt, order: .reverse),
                SortDescriptor(\Comment.id)
            ],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        List {
            taskSection
            peopleSection
            descriptionSection
            tagsSection
            commentsSection
        }
        .navigationTitle("Task")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                actionMenu
            }
        }
        .refreshable {
            await syncEngine.syncTaskDetail(taskID: taskID)
            await syncEngine.syncTaskComments(taskID: taskID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncTaskDetail(taskID: taskID)
            await syncEngine.syncTaskComments(taskID: taskID)
        }
        .task(id: taskID) {
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(nanoseconds: 14_000_000_000)
                guard !_Concurrency.Task.isCancelled else { break }
                guard activeSheet == nil, commentPendingDelete == nil else { continue }
                await syncEngine.syncTaskDetail(taskID: taskID)
                await syncEngine.syncTaskComments(taskID: taskID)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            presentedSheet(for: sheet)
        }
        .alert(
            "Delete Comment?",
            isPresented: Binding(
                get: { commentPendingDelete != nil },
                set: { isPresented in
                    if !isPresented { commentPendingDelete = nil }
                }
            ),
            presenting: commentPendingDelete
        ) { prompt in
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await syncEngine.deleteComment(commentID: prompt.id, taskID: taskID)
                    commentPendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                commentPendingDelete = nil
            }
        } message: { prompt in
            Text(prompt.body)
        }
    }

    private var actionMenu: some View {
        Menu {
            Button("Edit Description") { activeSheet = .description }
                .disabled(taskModel == nil)
            Button("Change Assignee") { activeSheet = .assignee }
                .disabled(taskModel == nil || allUsers.isEmpty)
            Button("Edit Tags") { activeSheet = .tags }
                .disabled(taskModel == nil || allTags.isEmpty)
            Button("Add Comment") { activeSheet = .comment }
                .disabled(taskModel == nil || allUsers.isEmpty)
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
                    .disabled(allUsers.isEmpty)
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

    @ViewBuilder
    private var tagsSection: some View {
        if taskModel != nil {
            Section("Tags") {
                Button("Edit Tags") {
                    activeSheet = .tags
                }
                .disabled(allTags.isEmpty)

                if tags.isEmpty {
                    Text("No tags")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags, id: \.id) { tag in
                        NavigationLink {
                            TagTasksView(tagID: tag.id, syncContainer: syncContainer, syncEngine: syncEngine)
                        } label: {
                            Label(tag.name, systemImage: "tag")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var commentsSection: some View {
        Section("Comments") {
            Button {
                activeSheet = .comment
            } label: {
                Label("Add Comment", systemImage: "plus.bubble")
            }
            .disabled(allUsers.isEmpty || taskModel == nil)

            if comments.isEmpty {
                Text("No comments")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comments, id: \.id) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comment.body)
                        Text("\(comment.authorName) · \(comment.createdAt.formatted(date: .numeric, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            commentPendingDelete = CommentDeletePrompt(id: comment.id, body: comment.body)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func taskStateMenu(taskModel: Task) -> some View {
        let projectID = taskModel.projectID
        return Menu {
            ForEach(DemoTaskStateOption.allCases) { option in
                Button {
                    _Concurrency.Task {
                        try? await syncEngine.updateTaskState(
                            taskID: taskID,
                            projectID: projectID,
                            state: option.rawValue
                        )
                    }
                } label: {
                    if taskModel.state == option.rawValue {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Text(DemoTaskStateOption(rawValue: taskModel.state)?.label ?? taskModel.state)
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
        case .tags:
            EditTaskTagsSheet(
                taskID: taskID,
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        case .comment:
            CreateCommentSheet(
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
                    LabeledContent("Role", value: userModel.role)
                } else {
                    Text("User not found")
                        .foregroundStyle(.secondary)
                }
            }

            taskBucketSection("Assigned", tasks: assignedTasks)
            taskBucketSection("Reviewer", tasks: reviewTasks)
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
                            Text(DemoTaskStateOption(rawValue: task.state)?.label ?? task.state)
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
    case tags
    case comment

    var id: String { rawValue }
}

private struct CommentDeletePrompt: Equatable {
    let id: String
    let body: String
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
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
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
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .presentationDetents([.medium, .large])
    }
}

private struct EditTaskTagsSheet: View {
    let taskID: String
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @SyncModel private var taskModel: Task?
    @SyncQuery private var allTags: [Tag]
    @SyncQuery private var selectedTags: [Tag]
    @State private var pendingTagIDs: Set<String> = []
    @State private var hasLoadedInitialSelection = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncEngine = syncEngine
        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer, animation: .snappy(duration: 0.22))
        _allTags = SyncQuery(
            Tag.self,
            in: syncContainer,
            sortBy: [\.name, \.id],
            animation: .snappy(duration: 0.22)
        )
        _selectedTags = SyncQuery(
            Tag.self,
            relatedTo: Task.self,
            relatedID: taskID,
            in: syncContainer,
            sortBy: [\.name, \.id],
            refreshOn: [\.tasks],
            animation: .snappy(duration: 0.22)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(allTags, id: \.id) { tag in
                    Button {
                        if pendingTagIDs.contains(tag.id) {
                            pendingTagIDs.remove(tag.id)
                        } else {
                            pendingTagIDs.insert(tag.id)
                        }
                    } label: {
                        HStack {
                            Text(tag.name)
                            Spacer()
                            if pendingTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Tags")
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
                        let tagIDs = pendingTagIDs.sorted()
                        _Concurrency.Task {
                            do {
                                try await syncEngine.replaceTaskTags(
                                    taskID: taskID,
                                    projectID: taskModel?.projectID,
                                    tagIDs: tagIDs
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
        .task(id: selectedTags.map(\.id).sorted()) {
            guard !hasLoadedInitialSelection, taskModel != nil else { return }
            pendingTagIDs = Set(selectedTags.map(\.id))
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
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CreateCommentSheet: View {
    let taskID: String
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss
    @SyncModel private var taskModel: Task?
    @SyncQuery private var users: [User]
    @State private var authorUserID: String?
    @State private var bodyText = ""
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
            Form {
                Section("Author") {
                    Picker("User", selection: $authorUserID) {
                        ForEach(users, id: \.id) { user in
                            Text(user.displayName).tag(Optional(user.id))
                        }
                    }
                }

                Section("Comment") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                }
            }
            .navigationTitle("New Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let authorUserID, !trimmedBody.isEmpty else { return }
                        isSaving = true
                        saveErrorMessage = nil
                        _Concurrency.Task {
                            do {
                                try await syncEngine.createComment(
                                    taskID: taskID,
                                    authorUserID: authorUserID,
                                    body: trimmedBody
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
                    .disabled(
                        isSaving ||
                        authorUserID == nil ||
                        bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .task(id: taskModel?.assigneeID) {
            seedAuthorIfNeeded()
        }
        .task(id: users.map(\.id)) {
            seedAuthorIfNeeded()
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

    private func seedAuthorIfNeeded() {
        guard !users.isEmpty else {
            authorUserID = nil
            return
        }

        let validIDs = Set(users.map(\.id))
        if let authorUserID, validIDs.contains(authorUserID) {
            return
        }

        authorUserID = taskModel?.assigneeID.flatMap { validIDs.contains($0) ? $0 : nil } ?? users.first?.id
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
