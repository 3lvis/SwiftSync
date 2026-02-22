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

    init(task: Task, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = task.id
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer)
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
            toMany: task,
            in: syncContainer,
            sortBy: [\.name, \.id],
            refreshOn: [\.tasks]
        )
        _comments = SyncQuery(
            Comment.self,
            toOne: task,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Comment.createdAt, order: .reverse),
                SortDescriptor(\Comment.id)
            ]
        )
    }

    var body: some View {
        List {
            taskSection
            descriptionSection
            tagsSection
            commentsSection
        }
        .navigationTitle(taskModel?.title ?? "Task")
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
                            TagTasksView(tag: tag, syncContainer: syncContainer, syncEngine: syncEngine)
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
        Menu {
            ForEach(DemoTaskStateOption.allCases) { option in
                Button {
                    _Concurrency.Task {
                        await syncEngine.updateTaskState(
                            taskID: taskID,
                            projectID: taskModel.projectID,
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

    @ViewBuilder
    private func presentedSheet(for sheet: TaskDetailSheet) -> some View {
        switch sheet {
        case .description:
            EditTaskDescriptionSheet(
                initialText: taskModel?.descriptionText ?? "",
                onSave: { newText in
                    await syncEngine.updateTaskDescription(
                        taskID: taskID,
                        projectID: taskModel?.projectID,
                        descriptionText: newText
                    )
                }
            )
        case .assignee:
            AssigneePickerSheet(
                users: allUsers,
                selectedAssigneeID: taskModel?.assigneeID,
                onSave: { newAssigneeID in
                    await syncEngine.updateTaskAssignee(
                        taskID: taskID,
                        projectID: taskModel?.projectID,
                        assigneeID: newAssigneeID
                    )
                }
            )
        case .tags:
            EditTaskTagsSheet(
                allTags: allTags,
                selectedTagIDs: Set(tags.map(\.id)),
                onSave: { selectedTagIDs in
                    await syncEngine.replaceTaskTags(
                        taskID: taskID,
                        projectID: taskModel?.projectID,
                        tagIDs: selectedTagIDs.sorted()
                    )
                }
            )
        case .comment:
            CreateCommentSheet(
                users: allUsers,
                defaultAuthorUserID: taskModel?.assigneeID ?? allUsers.first?.id,
                onSave: { authorUserID, body in
                    await syncEngine.createComment(
                        taskID: taskID,
                        authorUserID: authorUserID,
                        body: body
                    )
                }
            )
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
    let initialText: String
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(initialText: String, onSave: @escaping (String) async -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        _text = State(initialValue: initialText)
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
        }
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
                    _Concurrency.Task {
                        await onSave(trimmed)
                        await MainActor.run {
                            isSaving = false
                            dismiss()
                        }
                    }
                }) {
                    Text("Save")
                }
                .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AssigneePickerSheet: View {
    let users: [User]
    let selectedAssigneeID: String?
    let onSave: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingAssigneeID: String?
    @State private var isSaving = false

    init(
        users: [User],
        selectedAssigneeID: String?,
        onSave: @escaping (String?) async -> Void
    ) {
        self.users = users
        self.selectedAssigneeID = selectedAssigneeID
        self.onSave = onSave
        _pendingAssigneeID = State(initialValue: selectedAssigneeID)
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
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    isSaving = true
                    let selection = pendingAssigneeID
                    _Concurrency.Task {
                        await onSave(selection)
                        await MainActor.run {
                            isSaving = false
                            dismiss()
                        }
                    }
                }) {
                    Text("Save")
                }
                .disabled(isSaving)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct EditTaskTagsSheet: View {
    let allTags: [Tag]
    let selectedTagIDs: Set<String>
    let onSave: ([String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingTagIDs: Set<String>
    @State private var isSaving = false

    init(
        allTags: [Tag],
        selectedTagIDs: Set<String>,
        onSave: @escaping ([String]) async -> Void
    ) {
        self.allTags = allTags
        self.selectedTagIDs = selectedTagIDs
        self.onSave = onSave
        _pendingTagIDs = State(initialValue: selectedTagIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(allTags), id: \.id) { tag in
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
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    isSaving = true
                    let tagIDs = pendingTagIDs.sorted()
                    _Concurrency.Task {
                        await onSave(tagIDs)
                        await MainActor.run {
                            isSaving = false
                            dismiss()
                        }
                    }
                }) {
                    Text("Save")
                }
                .disabled(isSaving)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CreateCommentSheet: View {
    let users: [User]
    let defaultAuthorUserID: String?
    let onSave: (_ authorUserID: String, _ body: String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authorUserID: String?
    @State private var bodyText = ""
    @State private var isSaving = false

    init(
        users: [User],
        defaultAuthorUserID: String?,
        onSave: @escaping (_ authorUserID: String, _ body: String) async -> Void
    ) {
        self.users = users
        self.defaultAuthorUserID = defaultAuthorUserID
        self.onSave = onSave
        _authorUserID = State(initialValue: defaultAuthorUserID ?? users.first?.id)
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
        }
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
                    _Concurrency.Task {
                        await onSave(authorUserID, trimmedBody)
                        await MainActor.run {
                            isSaving = false
                            dismiss()
                        }
                    }
                }) {
                    Text("Save")
                }
                .disabled(
                    isSaving ||
                    authorUserID == nil ||
                    bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
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
