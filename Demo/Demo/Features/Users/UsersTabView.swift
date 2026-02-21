import SwiftData
import SwiftSync
import SwiftUI

struct UsersTabView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncQuery private var users: [User]
    @State private var hasTriggeredInitialSync = false

    init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        _users = SyncQuery(
            User.self,
            in: syncContainer,
            sortBy: [\.displayName, \.id]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(users, id: \.id) { user in
                    NavigationLink {
                        UserDetailView(user: user, syncContainer: syncContainer, syncEngine: syncEngine)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.headline)
                            Text(user.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if users.isEmpty && syncEngine.isSyncing {
                    ProgressView("Syncing users...")
                }
            }
            .navigationTitle("Users")
            .refreshable {
                await syncEngine.syncUsers()
            }
            .task {
                guard !hasTriggeredInitialSync else { return }
                hasTriggeredInitialSync = true
                await syncEngine.syncUsers()
            }
        }
    }
}

private struct UserDetailView: View {
    let user: User
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModel private var userModel: User?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(user: User, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.user = user
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _userModel = SyncModel(User.self, id: user.id, in: syncContainer)
        _tasks = SyncQuery(
            Task.self,
            parent: user,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.priority, order: .reverse),
                SortDescriptor(\Task.id)
            ],
            refreshOn: [\.project]
        )
    }

    var body: some View {
        List {
            Section {
                if let userModel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(userModel.displayName)
                            .font(.title3)
                        Text(userModel.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("User not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Assigned Tasks") {
                ForEach(tasks, id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(task: task, syncContainer: syncContainer, syncEngine: syncEngine)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.headline)
                            Text("\(task.state) · \(task.project?.name ?? task.projectID)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(userModel?.displayName ?? "User")
        .refreshable {
            await syncEngine.syncUserTasks(userID: user.id)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncUserTasks(userID: user.id)
        }
    }
}
