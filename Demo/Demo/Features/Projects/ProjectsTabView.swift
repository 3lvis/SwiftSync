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
#if DEBUG
    @State private var showingStressPrompt = false
#endif

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
        .refreshable {
            await syncEngine.loadProjectTasks(projectID: projectID, reason: .pullToRefresh)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.loadProjectTasks(projectID: projectID)
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
        .safeAreaInset(edge: .top) {
            if let status = syncEngine.status(for: statusKey) {
                HStack(spacing: 8) {
                    Text(statusSummary(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if status.phase == .failed {
                        Button("Retry") {
                            _Concurrency.Task {
                                await syncEngine.loadProjectTasks(projectID: projectID, reason: .retry)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.thinMaterial)
            }
        }
#if DEBUG
        .overlay(alignment: .bottom) {
            if syncEngine.isEarthquakeModeRunning,
               let status = syncEngine.earthquakeStatusText {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                    Text(status)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Stop") {
                        syncEngine.stopEarthquakeMode()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .alert("Stress test this screen?", isPresented: $showingStressPrompt) {
            Button("Start Stress", role: .destructive) {
                syncEngine.startEarthquakeMode(for: .projectDetail(projectID: projectID))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Debug-only Earthquake Mode runs finite add/edit/delete overlap for this project screen.")
        }
        .background(
            ShakeDetector {
                guard !syncEngine.isEarthquakeModeRunning else { return }
                showingStressPrompt = true
            }
            .allowsHitTesting(false)
        )
#endif
    }

    private var statusKey: DataKey {
        DataKey(namespace: "projectTasks", id: projectID)
    }

    private func statusSummary(_ status: ScopeSyncStatus) -> String {
        switch status.phase {
        case .loading:
            return status.path == .networkFirst ? "Network-first loading..." : "Loading..."
        case .refreshing:
            return "Local-first refresh in progress..."
        case .failed:
            return status.errorMessage ?? "Sync failed"
        case .idle:
            return status.path == .networkFirst ? "Loaded from network" : "Using local cache + refresh"
        }
    }
}

private struct TaskDeletePrompt: Equatable {
    let id: String
    let title: String
}
