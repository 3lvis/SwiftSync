import SwiftData
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let task: Task
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var taskModel: Task?
    @SyncQuery private var tags: [Tag]
    @SyncQuery private var comments: [Comment]
    @State private var hasTriggeredInitialSync = false

    init(task: Task, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.task = task
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        let taskID = task.id

        _taskModel = SyncModel(Task.self, id: taskID, in: syncContainer)

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
            ],
            refreshOn: [\.authorUser]
        )
    }

    var body: some View {
        List {
            Section("Task") {
                if let taskModel {
                    Text(taskModel.title)
                        .font(.title3)
                    Text("State: \(taskModel.state)")
                    Text("Priority: \(taskModel.priority)")
                    if let assignee = taskModel.assignee?.displayName {
                        Text("Assignee: \(assignee)")
                    }
                } else {
                    Text("Task not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Description") {
                Text(taskModel?.descriptionText ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if taskModel != nil {
                Section("Tags") {
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
        .navigationTitle(taskModel?.title ?? "Task")
        .refreshable {
            await syncEngine.syncTaskDetail(taskID: task.id)
            await syncEngine.syncTaskComments(taskID: task.id)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncTaskDetail(taskID: task.id)
            await syncEngine.syncTaskComments(taskID: task.id)
        }
    }
}
