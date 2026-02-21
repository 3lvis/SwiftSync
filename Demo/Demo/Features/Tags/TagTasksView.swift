import SwiftData
import SwiftSync
import SwiftUI

struct TagTasksView: View {
    let tagID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var tag: Tag?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(tagID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.tagID = tagID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        _tag = SyncModel(Tag.self, id: tagID, in: syncContainer)

        let predicate = #Predicate<Task> { task in
            task.tags.contains { $0.id == tagID }
        }
        _tasks = SyncQuery(
            Task.self,
            predicate: predicate,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.priority, order: .reverse),
                SortDescriptor(\Task.id)
            ]
        )
    }

    var body: some View {
        List {
            if let tag {
                Section {
                    Text(tag.name)
                        .font(.title3)
                    Text("\(tasks.count) tasks")
                        .foregroundStyle(.secondary)
                }

                Section("Tasks") {
                    ForEach(tasks, id: \.id) { task in
                        NavigationLink {
                            TaskDetailView(taskID: task.id, syncContainer: syncContainer, syncEngine: syncEngine)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title)
                                    .font(.headline)
                                Text("\(task.state) · p\(task.priority)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Tag not found")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(tag?.name ?? "Tag")
        .refreshable {
            await syncEngine.syncTagTasks(tagID: tagID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncTagTasks(tagID: tagID)
        }
    }
}
