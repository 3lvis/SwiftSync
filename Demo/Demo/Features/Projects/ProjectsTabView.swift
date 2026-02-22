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
                            project: project,
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
    let project: Project
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var projectModel: Project?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(project: Project, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.project = project
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _projectModel = SyncModel(Project.self, id: project.id, in: syncContainer)
        _tasks = SyncQuery(
            Task.self,
            toOne: project,
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
                if let projectModel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(projectModel.name)
                            .font(.title3)
                        Text("Status: \(projectModel.status)")
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
                        TaskDetailView(task: task, syncContainer: syncContainer, syncEngine: syncEngine)
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
        .navigationTitle(projectModel?.name ?? "Project")
        .refreshable {
            await syncEngine.syncProjectTasks(projectID: project.id)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncProjectTasks(projectID: project.id)
        }
    }
}
