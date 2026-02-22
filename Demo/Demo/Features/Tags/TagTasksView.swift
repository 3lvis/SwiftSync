import SwiftData
import SwiftSync
import SwiftUI

struct TagTasksView: View {
    let tag: Tag
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var tagModel: Tag?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(tag: Tag, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.tag = tag
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        _tagModel = SyncModel(Tag.self, id: tag.id, in: syncContainer)

        _tasks = SyncQuery(
            Task.self,
            toMany: tag,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.priority, order: .reverse),
                SortDescriptor(\Task.id)
            ],
            refreshOn: [\.tags]
        )
    }

    var body: some View {
        List {
            if let tagModel {
                Section {
                    Text(tagModel.name)
                        .font(.title3)
                    Text("\(tasks.count) tasks")
                        .foregroundStyle(.secondary)
                }

                Section("Tasks") {
                    ForEach(tasks, id: \.id) { task in
                        NavigationLink {
                            TaskDetailView(task: task, syncContainer: syncContainer, syncEngine: syncEngine)
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
        .navigationTitle(tagModel?.name ?? "Tag")
        .refreshable {
            await syncEngine.syncTagTasks(tagID: tag.id)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncTagTasks(tagID: tag.id)
        }
    }
}
