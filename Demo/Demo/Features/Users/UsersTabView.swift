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
        _users = SyncQuery(User.self, in: syncContainer)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(users.sorted(by: { $0.displayName < $1.displayName }), id: \.id) { user in
                    NavigationLink {
                        UserDetailView(userID: user.id, syncContainer: syncContainer, syncEngine: syncEngine)
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
    let userID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @SyncModelValue private var user: User?
    @SyncQuery private var tasks: [Task]
    @State private var hasTriggeredInitialSync = false

    init(userID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.userID = userID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _user = SyncModelValue(User.self, id: userID, in: syncContainer)

        let predicate = #Predicate<Task> { row in
            row.assigneeID == userID
        }
        _tasks = SyncQuery(Task.self, predicate: predicate, in: syncContainer)
    }

    var body: some View {
        List {
            Section {
                if let user {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.displayName)
                            .font(.title3)
                        Text(user.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("User not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Assigned Tasks") {
                ForEach(tasks.sorted(by: { $0.priority > $1.priority }), id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(taskID: task.id, syncContainer: syncContainer, syncEngine: syncEngine)
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
        .navigationTitle(user?.displayName ?? "User")
        .refreshable {
            await syncEngine.syncUserTasks(userID: userID)
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            await syncEngine.syncUserTasks(userID: userID)
        }
    }
}
