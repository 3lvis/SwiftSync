import SwiftSync
import SwiftUI

struct TagTasksView: View {
    let tagID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModelValue private var tag: Tag?
    @State private var hasTriggeredInitialSync = false

    init(tagID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.tagID = tagID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        _tag = SyncModelValue(Tag.self, id: tagID, in: syncContainer)
    }

    var body: some View {
        List {
            if let tag {
                Section {
                    Text(tag.name)
                        .font(.title3)
                    Text("\(tag.tasks.count) tasks")
                        .foregroundStyle(.secondary)
                }

                Section("Tasks") {
                    ForEach(tag.tasks.sorted(by: { $0.priority > $1.priority }), id: \.id) { task in
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
