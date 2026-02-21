import SwiftData
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var task: Task?
    @SyncQuery private var tags: [Tag]
    @SyncQuery private var comments: [Comment]
    @State private var hasTriggeredInitialSync = false

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _task = SyncModel(Task.self, id: taskID, in: syncContainer)

        let predicate = #Predicate<Comment> { row in
            row.taskID == taskID
        }
        let tagsPredicate = #Predicate<Tag> { tag in
            tag.tasks.contains { $0.id == taskID }
        }
        _tags = SyncQuery(
            Tag.self,
            predicate: tagsPredicate,
            in: syncContainer,
            sortBy: [\.name, \.id],
            refreshOn: [\.tasks]
        )
        _comments = SyncQuery(
            Comment.self,
            predicate: predicate,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Comment.createdAt, order: .reverse),
                SortDescriptor(\Comment.id)
            ],
            refreshOn: [\.authorUser]
        )
    }

    var body: some View {
        List {
            Section("Task") {
                if let task {
                    Text(task.title)
                        .font(.title3)
                    Text("State: \(task.state)")
                    Text("Priority: \(task.priority)")
                    if let assignee = task.assignee?.displayName {
                        Text("Assignee: \(assignee)")
                    }
                    if let dueDate = task.dueDate {
                        Text("Due: \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                } else {
                    Text("Task not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Description") {
                Text(task?.descriptionText ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if task != nil {
                Section("Tags") {
                    if tags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tags, id: \.id) { tag in
                            NavigationLink {
                                TagTasksView(tagID: tag.id, syncContainer: syncContainer, syncEngine: syncEngine)
                            } label: {
                                Label(tag.name, systemImage: "tag")
                                    .foregroundStyle(Color(hex: tag.colorHex) ?? .accentColor)
                            }
                        }
                    }
                }
            }

            Section("Comments") {
                if comments.isEmpty {
                    Text("No comments")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comments, id: \.id) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.body)
                            Text("\(comment.authorUser?.displayName ?? comment.authorUserID) · \(comment.createdAt.formatted(date: .numeric, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(task?.title ?? "Task")
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
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
