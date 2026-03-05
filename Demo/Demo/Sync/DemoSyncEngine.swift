import Combine
import Foundation
import SwiftData
import SwiftSync

@MainActor
final class DemoSyncEngine: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var scopeStatus: [DataKey: ScopeSyncStatus] = [:]

#if DEBUG
    @Published private(set) var isEarthquakeModeRunning = false
    @Published private(set) var earthquakeStatusText: String?

    enum EarthquakeScope: Equatable {
        case projectDetail(projectID: String)
        case taskDetail(taskID: String)
    }
#endif

    private(set) var hasBootstrapped = false
    private var inFlightOperations: Set<String> = []
    private var lastSuccessfulSyncByDataKey: [DataKey: Date] = [:]

    private let syncContainer: SyncContainer
    private let apiClient: FakeDemoAPIClient
    private let freshnessPolicy = DataFreshnessPolicy(
        defaultTTL: 120,
        ttlByNamespace: [
            DemoDataNamespace.projects: 300,
            DemoDataNamespace.users: 300,
            DemoDataNamespace.taskStates: 600,
            DemoDataNamespace.userRoles: 600,
            DemoDataNamespace.projectTasks: 20,
            DemoDataNamespace.taskDetail: 20
        ]
    )

#if DEBUG
    private var earthquakeRunner: FiniteAsyncRunner?
#endif

    init(syncContainer: SyncContainer, apiClient: FakeDemoAPIClient) {
        self.syncContainer = syncContainer
        self.apiClient = apiClient
    }

#if DEBUG
    func startEarthquakeMode(for scope: EarthquakeScope) {
        guard !isEarthquakeModeRunning else { return }

        let runner = FiniteAsyncRunner(
            sleep: { nanos in
                if nanos > 0 {
                    try await _Concurrency.Task.sleep(nanoseconds: nanos)
                }
            },
            operation: { [weak self] iteration in
                guard let self else { return }
                await self.runEarthquakeIteration(scope: scope, iteration: iteration)
            },
            onStop: { [weak self] in
                guard let self else { return }
                self.isEarthquakeModeRunning = false
                self.earthquakeStatusText = nil
                self.earthquakeRunner = nil
            }
        )

        earthquakeRunner = runner
        isEarthquakeModeRunning = true
        earthquakeStatusText = scope.label
        runner.start(maxIterations: 20, intervalNanoseconds: 2_250_000_000)
    }

    func stopEarthquakeMode() {
        earthquakeRunner?.stop()
        earthquakeRunner = nil
        isEarthquakeModeRunning = false
        earthquakeStatusText = nil
    }

    private func runEarthquakeIteration(scope: EarthquakeScope, iteration: Int) async {
        switch scope {
        case .projectDetail(let projectID):
            async let refresh: Void = syncProjectTasks(projectID: projectID)
            async let mutation: Void = runProjectStressMutation(projectID: projectID, iteration: iteration)
            _ = await (refresh, mutation)

        case .taskDetail(let taskID):
            let loadedTask: Task?
            do {
                loadedTask = try task(withID: taskID)
            } catch {
                loadedTask = nil
            }
            guard let projectID = loadedTask?.projectID else {
                await syncTaskDetail(taskID: taskID)
                return
            }
            async let detailRefresh: Void = syncTaskDetail(taskID: taskID)
            async let projectRefresh: Void = syncProjectTasks(projectID: projectID)
            async let mutation: Void = runTaskDetailStressMutation(taskID: taskID, projectID: projectID, iteration: iteration)
            _ = await (detailRefresh, projectRefresh, mutation)
        }
    }

    private func runProjectStressMutation(projectID: String, iteration: Int) async {
        guard let body = try? makeStressTaskBody(projectID: projectID, iteration: iteration) else { return }
        do {
            let created = try await apiClient.createTask(body: body)
            guard let createdID = created["id"] as? String else {
                try await syncProjectTasksInternal(projectID: projectID)
                return
            }

            var updated = body
            updated["id"] = createdID
            updated["title"] = "[EQ] Updated \(iteration)"
            updated["description"] = "Earthquake update iteration \(iteration)."

            _ = try await apiClient.updateTask(taskID: createdID, body: updated)
            try await apiClient.deleteTask(taskID: createdID)
            try await syncProjectTasksInternal(projectID: projectID)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runTaskDetailStressMutation(taskID: String, projectID: String, iteration: Int) async {
        do {
            guard let existing = try task(withID: taskID),
                  let baseBody = try taskPayload(for: existing)
            else { return }

            var edited = baseBody
            edited["title"] = "\(existing.title) [EQ \(iteration)]"
            edited["description"] = "\(existing.descriptionText)\n\nEarthquake touch #\(iteration)"
            let users = try allUsers()
            if !users.isEmpty {
                if iteration.isMultiple(of: 3) {
                    edited["assignee_id"] = NSNull()
                } else {
                    let assignee = users[iteration % users.count]
                    edited["assignee_id"] = assignee.id
                }
            }
            _ = try await apiClient.updateTask(taskID: taskID, body: edited)

            if !users.isEmpty {
                let reviewerIDs = rotatingIDs(from: users, iteration: iteration, count: min(2, users.count))
                let watcherIDs = rotatingIDs(from: users, iteration: iteration + 1, count: min(3, users.count))
                _ = try await apiClient.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs)
                _ = try await apiClient.replaceTaskWatchers(taskID: taskID, watcherIDs: watcherIDs)
            }

            if let createdBody = try makeStressTaskBody(projectID: projectID, iteration: iteration + 1000) as [String: Any]? {
                let created = try await apiClient.createTask(body: createdBody)
                if let createdID = created["id"] as? String {
                    try await apiClient.deleteTask(taskID: createdID)
                }
            }

            try await syncTaskAfterMutation(taskID: taskID, projectID: projectID)
            try await syncProjectTasksInternal(projectID: projectID)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func makeStressTaskBody(projectID: String, iteration: Int) throws -> [String: Any]? {
        guard let author = try firstUser(),
              let state = try firstTaskState()
        else { return nil }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        let taskID = UUID().uuidString

        return [
            "id": taskID,
            "project_id": projectID,
            "assignee_id": NSNull(),
            "author_id": author.id,
            "title": "[EQ] Temp \(iteration)",
            "description": "Earthquake temp task for iteration \(iteration).",
            "state": ["id": state.id, "label": state.label],
            "created_at": formatter.string(from: now),
            "updated_at": formatter.string(from: now)
        ]
    }

    private func taskPayload(for task: Task) throws -> [String: Any]? {
        guard let state = try taskState(withID: task.state) ?? firstTaskState() else { return nil }
        let formatter = ISO8601DateFormatter()

        return [
            "id": task.id,
            "project_id": task.projectID,
            "assignee_id": task.assigneeID ?? NSNull(),
            "author_id": task.authorID,
            "title": task.title,
            "description": task.descriptionText,
            "state": ["id": state.id, "label": state.label],
            "created_at": formatter.string(from: task.createdAt),
            "updated_at": formatter.string(from: task.updatedAt)
        ]
    }

    private func firstUser() throws -> User? {
        try syncContainer.mainContext
            .fetch(FetchDescriptor<User>(sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)]))
            .first
    }

    private func allUsers() throws -> [User] {
        try syncContainer.mainContext.fetch(
            FetchDescriptor<User>(sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)])
        )
    }

    private func rotatingIDs(from users: [User], iteration: Int, count: Int) -> [String] {
        guard !users.isEmpty, count > 0 else { return [] }
        var ids: [String] = []
        for offset in 0..<count {
            ids.append(users[(iteration + offset) % users.count].id)
        }
        return Array(Set(ids)).sorted()
    }

    private func firstTaskState() throws -> TaskStateOption? {
        try syncContainer.mainContext
            .fetch(FetchDescriptor<TaskStateOption>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)]))
            .first
    }

    private func taskState(withID id: String) throws -> TaskStateOption? {
        let descriptor = FetchDescriptor<TaskStateOption>(predicate: #Predicate { $0.id == id })
        return try syncContainer.mainContext.fetch(descriptor).first
    }

    private func task(withID taskID: String) throws -> Task? {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID })
        return try syncContainer.mainContext.fetch(descriptor).first
    }
#endif

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await syncInitialData()
    }

    func syncInitialData() async {
        await syncOperation("initial") {
            try await syncProjectsInternal()
            try await syncUsersInternal()
            try await syncTaskStatesInternal()
            try await syncUserRolesInternal()
        }
    }

    func syncProjects() async {
        await syncOperation("projects") {
            try await syncProjectsInternal()
        }
    }

    func loadProjectsScreen() async {
        let key = DataKey(namespace: DemoDataNamespace.projects)
        await runScreenLoad(statusKey: key, dataKeys: [key]) {
            await self.syncProjects()
        }
    }

    func syncUsers() async {
        await syncOperation("users") {
            try await syncUsersInternal()
        }
    }

    func syncTaskStates() async {
        await syncOperation("taskStates") {
            try await syncTaskStatesInternal()
        }
    }

    func syncUserRoles() async {
        await syncOperation("userRoles") {
            try await syncUserRolesInternal()
        }
    }

    func syncProjectTasks(projectID: String) async {
        await syncOperation("projectTasks-\(projectID)") {
            try await syncProjectTasksInternal(projectID: projectID)
        }
    }

    func loadProjectDetailScreen(projectID: String) async {
        let key = DataKey(namespace: DemoDataNamespace.projectTasks, id: projectID)
        await runScreenLoad(statusKey: key, dataKeys: [key]) {
            await self.syncProjectTasks(projectID: projectID)
        }
    }

    func syncTaskDetail(taskID: String) async {
        await syncOperation("taskDetail-\(taskID)") {
            try await syncTaskDetailInternal(taskID: taskID)
        }
    }

    func loadTaskDetailScreen(taskID: String) async {
        let key = DataKey(namespace: DemoDataNamespace.taskDetailScreen, id: taskID)
        let detailKey = DataKey(namespace: DemoDataNamespace.taskDetail, id: taskID)
        await runScreenLoad(statusKey: key, dataKeys: [detailKey]) {
            await self.syncTaskDetail(taskID: taskID)
        }
    }

    func loadTaskFormScreen() async {
        let key = DataKey(namespace: DemoDataNamespace.taskFormMetadata)
        let usersKey = DataKey(namespace: DemoDataNamespace.users)
        let statesKey = DataKey(namespace: DemoDataNamespace.taskStates)
        await runScreenLoad(statusKey: key, dataKeys: [usersKey, statesKey]) {
            await self.syncUsers()
            await self.syncTaskStates()
        }
    }

    func status(for key: DataKey) -> ScopeSyncStatus? {
        scopeStatus[key]
    }

    func createTask(body: [String: Any], projectID: String) async throws {
        try await syncOperationThrowing("createTask-\(projectID)") {
            _ = try await apiClient.createTask(body: body)
            try await syncProjectTasksInternal(projectID: projectID)
        }
    }

    func updateTask(taskID: String, projectID: String?, body: [String: Any]) async throws {
        try await syncOperationThrowing("updateTask-\(taskID)") {
            _ = try await apiClient.updateTask(taskID: taskID, body: body)
            try await syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    func deleteTask(taskID: String, projectID: String) async {
        await syncOperation("deleteTask-\(taskID)") {
            try await apiClient.deleteTask(taskID: taskID)
            try await syncProjectTasksInternal(projectID: projectID)
        }
    }

    func replaceTaskReviewers(taskID: String, projectID: String?, reviewerIDs: [String]) async throws {
        try await syncOperationThrowing("replaceTaskReviewers-\(taskID)") {
            _ = try await self.apiClient.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs)
            try await self.syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    func replaceTaskWatchers(taskID: String, projectID: String?, watcherIDs: [String]) async throws {
        try await syncOperationThrowing("replaceTaskWatchers-\(taskID)") {
            _ = try await self.apiClient.replaceTaskWatchers(taskID: taskID, watcherIDs: watcherIDs)
            try await self.syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    private func syncProjectsInternal() async throws {
        let payload = try await apiClient.getProjects()
        try await syncContainer.sync(payload: payload, as: Project.self)
        markDataSynced(DataKey(namespace: DemoDataNamespace.projects))
    }

    private func syncUsersInternal() async throws {
        let payload = try await apiClient.getUsers()
        try await syncContainer.sync(payload: payload, as: User.self)
        markDataSynced(DataKey(namespace: DemoDataNamespace.users))
    }

    private func syncTaskStatesInternal() async throws {
        let payload = try await apiClient.getTaskStateOptions()
        try await syncContainer.sync(payload: payload, as: TaskStateOption.self)
        markDataSynced(DataKey(namespace: DemoDataNamespace.taskStates))
    }

    private func syncUserRolesInternal() async throws {
        let payload = try await apiClient.getUserRoleOptions()
        try await syncContainer.sync(payload: payload, as: UserRoleOption.self)
        markDataSynced(DataKey(namespace: DemoDataNamespace.userRoles))
    }

    private func syncProjectTasksInternal(projectID: String) async throws {
        let payload = try await apiClient.getProjectTasks(projectID: projectID)

        if try project(withID: projectID) == nil {
            let projectsPayload = try await apiClient.getProjects()
            try await syncContainer.sync(payload: projectsPayload, as: Project.self)
        }

        guard let project = try project(withID: projectID) else { return }
        try await syncContainer.sync(payload: payload, as: Task.self, parent: project)
        markDataSynced(DataKey(namespace: DemoDataNamespace.projectTasks, id: projectID))
        try await syncProjectsInternal()
    }

    private func syncTaskDetailInternal(taskID: String) async throws {
        guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
        try await syncContainer.sync(item: payload, as: Task.self)
        markDataSynced(DataKey(namespace: DemoDataNamespace.taskDetail, id: taskID))
    }

    /// Canonical post-mutation sync sequence for a single task.
    /// Project list syncs first (broad refresh), task detail syncs last so its
    /// authoritative relationship payload always wins over any stale list snapshot.
    private func syncTaskAfterMutation(taskID: String, projectID: String?) async throws {
        if let projectID {
            try await syncProjectTasksInternal(projectID: projectID)
        }
        try await syncTaskDetailInternal(taskID: taskID)
    }

    private func syncOperation(_ key: String, _ operation: () async throws -> Void) async {
        do {
            try await syncOperationThrowing(key, operation)
        } catch {
            // Background refresh callers rely on global sync status, not thrown errors.
        }
    }

    private func syncOperationThrowing(_ key: String, _ operation: () async throws -> Void) async throws {
        guard !inFlightOperations.contains(key) else { return }

        inFlightOperations.insert(key)
        isSyncing = true

        defer {
            inFlightOperations.remove(key)
            isSyncing = !inFlightOperations.isEmpty
        }

        do {
            try await operation()
            lastErrorMessage = nil
            lastSyncDate = Date()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastErrorMessage = message
            throw error
        }
    }

    private func project(withID projectID: String) throws -> Project? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Project>()).first { $0.id == projectID }
    }

    private func markDataSynced(_ key: DataKey, at date: Date = Date()) {
        lastSuccessfulSyncByDataKey[key] = date
    }

    private func runScreenLoad(
        statusKey: DataKey,
        dataKeys: [DataKey],
        networkFetch: @escaping @MainActor () async -> Void
    ) async {
        let decisions = dataKeys.map { key in
            decisionForData(key: key, hasLocalData: hasLocalData(for: key))
        }
        let path = ScreenLoadPlanner.path(decisions: decisions)

        scopeStatus[statusKey] = ScopeSyncStatusReducer.start(path: path)

        if path == .localFirstRefresh {
            _Concurrency.Task { @MainActor in
                await networkFetch()
                self.finalizeScopeStatus(key: statusKey)
            }
            return
        }

        await networkFetch()
        finalizeScopeStatus(key: statusKey)
    }

    private func finalizeScopeStatus(key: DataKey) {
        guard let previous = scopeStatus[key] else { return }

        if let message = lastErrorMessage {
            scopeStatus[key] = ScopeSyncStatusReducer.fail(previous: previous, errorMessage: message)
            return
        }

        scopeStatus[key] = ScopeSyncStatusReducer.succeed(previous: previous)
    }

    private func decisionForData(key: DataKey, hasLocalData: Bool, now: Date = Date()) -> LoadDecision {
        freshnessPolicy.decision(
            for: key,
            hasLocalData: hasLocalData,
            lastSuccessfulSync: lastSuccessfulSyncByDataKey[key],
            now: now
        )
    }

    private func hasLocalProjects() -> Bool {
        (try? syncContainer.mainContext.fetch(FetchDescriptor<Project>()).isEmpty == false) ?? false
    }

    private func hasLocalUsers() -> Bool {
        (try? syncContainer.mainContext.fetch(FetchDescriptor<User>()).isEmpty == false) ?? false
    }

    private func hasLocalTaskStates() -> Bool {
        (try? syncContainer.mainContext.fetch(FetchDescriptor<TaskStateOption>()).isEmpty == false) ?? false
    }

    private func hasLocalUserRoles() -> Bool {
        (try? syncContainer.mainContext.fetch(FetchDescriptor<UserRoleOption>()).isEmpty == false) ?? false
    }

    private func hasLocalProjectTasks(projectID: String) -> Bool {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.projectID == projectID })
        return (try? syncContainer.mainContext.fetch(descriptor).isEmpty == false) ?? false
    }

    private func hasLocalTaskDetail(taskID: String) -> Bool {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID })
        return (try? syncContainer.mainContext.fetch(descriptor).isEmpty == false) ?? false
    }

    private func hasLocalData(for key: DataKey) -> Bool {
        switch key.namespace {
        case DemoDataNamespace.projects:
            return hasLocalProjects()
        case DemoDataNamespace.users:
            return hasLocalUsers()
        case DemoDataNamespace.taskStates:
            return hasLocalTaskStates()
        case DemoDataNamespace.userRoles:
            return hasLocalUserRoles()
        case DemoDataNamespace.projectTasks:
            guard let projectID = key.id else { return false }
            return hasLocalProjectTasks(projectID: projectID)
        case DemoDataNamespace.taskDetail:
            guard let taskID = key.id else { return false }
            return hasLocalTaskDetail(taskID: taskID)
        default:
            return false
        }
    }
}

private enum DemoDataNamespace {
    static let projects = "projects"
    static let users = "users"
    static let taskStates = "taskStates"
    static let userRoles = "userRoles"
    static let projectTasks = "projectTasks"
    static let taskDetail = "taskDetail"
    static let taskDetailScreen = "taskDetailScreen"
    static let taskFormMetadata = "taskFormMetadata"
}

#if DEBUG
private extension DemoSyncEngine.EarthquakeScope {
    var label: String {
        switch self {
        case .projectDetail:
            return "Earthquake Mode running: Project detail"
        case .taskDetail:
            return "Earthquake Mode running: Task detail"
        }
    }
}
#endif
