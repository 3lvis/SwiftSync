import SwiftSync
import SwiftUI
import UIKit

struct ProjectsTabView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine
    @State private var selectedProjectID: String?

    var body: some View {
        NavigationStack {
            _ProjectsRepresentable(syncContainer: syncContainer, syncEngine: syncEngine) { projectID in
                selectedProjectID = projectID
            }
            .navigationTitle("Projects")
            .navigationDestination(item: $selectedProjectID) { projectID in
                ProjectDetailView(
                    projectID: projectID,
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
    }
}

private struct _ProjectsRepresentable: UIViewControllerRepresentable {
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine
    let onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> ProjectsViewController {
        ProjectsViewController(syncContainer: syncContainer, syncEngine: syncEngine, onSelect: onSelect)
    }

    func updateUIViewController(_ uiViewController: ProjectsViewController, context: Context) {}
}

// MARK: - Project Detail

private struct ProjectDetailView: View {
    let projectID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var projectModel: Project?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false
    @State private var isShowingCreateTaskSheet = false
    @State private var taskPendingDelete: TaskDeletePrompt?

    init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = projectID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _projectModel = SyncModel(Project.self, id: projectID, in: syncContainer)
        _tasks = SyncQuery(
            Task.self,
            relatedTo: Project.self,
            relatedID: projectID,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.id)
            ],
            refreshOn: [\.assignee],
            animation: .snappy(duration: 0.24)
        )
    }

    var body: some View {
        List {
            Section {
                if let projectModel {
                    Text(projectModel.name)
                        .font(.headline)
                        .lineLimit(3)

                    LabeledContent("Tasks", value: projectModel.taskCount == 1 ? "1 task" : "\(projectModel.taskCount) tasks")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Project not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tasks") {
                ForEach(tasks, id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(taskID: task.id, syncContainer: syncContainer, syncEngine: syncEngine)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(.headline)
                                .lineLimit(3)

                            HStack(spacing: 8) {
                                Text(task.stateLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if let assignee = task.assignee?.displayName {
                                    Text("Assignee: \(assignee)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            taskPendingDelete = TaskDeletePrompt(id: task.id, title: task.title)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCreateTaskSheet = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.loadProjectDetailScreen(projectID: projectID)
        }
        .onAppear {
#if DEBUG
            syncEngine.setActiveEarthquakeScope(.projectDetail(projectID: projectID))
#endif
        }
        .onDisappear {
#if DEBUG
            syncEngine.setActiveEarthquakeScope(nil)
#endif
        }
        .sheet(isPresented: $isShowingCreateTaskSheet) {
            TaskFormSheet(
                mode: .create(projectID: projectID),
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        }
        .alert(
            "Delete Task?",
            isPresented: Binding(
                get: { taskPendingDelete != nil },
                set: { if !$0 { taskPendingDelete = nil } }
            ),
            presenting: taskPendingDelete
        ) { prompt in
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    await syncEngine.deleteTask(taskID: prompt.id, projectID: projectID)
                    taskPendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { taskPendingDelete = nil }
        } message: { prompt in
            Text("Delete \"\(prompt.title)\" from this project?")
        }
    }
}

private struct TaskDeletePrompt: Equatable {
    let id: String
    let title: String
}
