import SwiftData
import SwiftSync
import SwiftUI

struct ProjectsTabView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncQuery private var projects: [Project]
    @State private var hasTriggeredInitialSync = false

    init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        _projects = SyncQuery(
            Project.self,
            in: syncContainer,
            sortBy: [\.name, \.id]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(projects, id: \.id) { project in
                    NavigationLink {
                        ProjectDetailView(
                            projectID: project.id,
                            syncContainer: syncContainer,
                            syncEngine: syncEngine
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.headline)
                            Text(project.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if projects.isEmpty && syncEngine.isSyncing {
                    ProgressView("Syncing projects...")
                }
            }
            .navigationTitle("Projects")
            .refreshable {
                await syncEngine.syncProjects()
                await syncEngine.syncTags()
            }
            .task {
                guard !hasTriggeredInitialSync else { return }
                hasTriggeredInitialSync = true
                await syncEngine.syncProjects()
                await syncEngine.syncTags()
            }
        }
    }
}

private struct ProjectDetailView: View {
    let projectID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var project: Project?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = projectID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _project = SyncModel(Project.self, id: projectID, in: syncContainer)

        let predicate = #Predicate<Task> { row in
            row.projectID == projectID
        }
        _tasks = SyncQuery(
            Task.self,
            predicate: predicate,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.priority, order: .reverse),
                SortDescriptor(\Task.id)
            ],
            refreshOn: [\.assignee]
        )
    }

    var body: some View {
        List {
            Section {
                if let project {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(project.name)
                            .font(.title3)
                        Text("Status: \(project.status)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.headline)
                            Text("\(task.state) · p\(task.priority)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let assignee = task.assignee?.displayName {
                                Text("Assignee: \(assignee)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(project?.name ?? "Project")
        .refreshable {
            await syncEngine.syncProjectTasks(projectID: projectID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncProjectTasks(projectID: projectID)
        }
    }
}
