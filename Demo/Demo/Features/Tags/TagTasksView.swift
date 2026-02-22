import SwiftData
import SwiftSync
import SwiftUI

struct TagTasksView: View {
    let tagID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var tagModel: Tag?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(tag: Tag, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.tagID = tag.id
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        _tagModel = SyncModel(Tag.self, id: tag.id, in: syncContainer, animation: .snappy(duration: 0.22))

        _tasks = SyncQuery(
            Task.self,
            toMany: tag,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.id)
            ],
            refreshOn: [\.tags],
            animation: .snappy(duration: 0.22)
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
                                Text(task.state)
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
            await syncEngine.syncTagTasks(tagID: tagID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncTagTasks(tagID: tagID)
        }
        .task(id: tagID) {
            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(nanoseconds: 6_500_000_000)
                guard !_Concurrency.Task.isCancelled else { break }
                await syncEngine.syncTagTasks(tagID: tagID)
            }
        }
    }
}
