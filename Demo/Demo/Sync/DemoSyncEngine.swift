import Combine
import Foundation
import SwiftData
import SwiftSync

@MainActor
final class DemoSyncEngine: ObservableObject {
    private enum SyncTaskDetailError: LocalizedError {
        case missingProjectID
        case missingProject(String)

        var errorDescription: String? {
            switch self {
            case .missingProjectID:
                return "Task detail payload is missing project_id."
            case let .missingProject(projectID):
                return "Task detail sync requires project \(projectID) to exist locally."
            }
        }
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var lastErrorMessage: String?

#if DEBUG
    @Published private(set) var isEarthquakeModeRunning = false
    @Published private(set) var earthquakeStatusText: String?

    enum EarthquakeScope: Equatable {
        case projectDetail(projectID: String)
        case taskDetail(taskID: String)
    }
#endif

    private var inFlightOperations: Set<String> = []

    private let syncContainer: SyncContainer
    private let apiClient: FakeDemoAPIClient

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
            do {
                try await syncProjectTasks(projectID: projectID)
            } catch {
                lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await runProjectStressMutation(projectID: projectID, iteration: iteration)

        case .taskDetail(let taskID):
            let loadedTask: Task?
            do {
                loadedTask = try task(withID: taskID)
            } catch {
                loadedTask = nil
            }
            guard let projectID = loadedTask?.projectID else {
                do {
                    try await syncTaskDetail(taskID: taskID)
                } catch {
                    lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                return
            }
            do {
                try await syncTaskDetail(taskID: taskID)
                try await syncProjectTasks(projectID: projectID)
            } catch {
                lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            await runTaskDetailStressMutation(taskID: taskID, projectID: projectID, iteration: iteration)
        }
    }

    private func runProjectStressMutation(projectID: String, iteration: Int) async {
        guard let body = try? makeStressTaskBody(projectID: projectID, iteration: iteration) else { return }
        do {
            let created = try await apiClient.createTask(body: body)
            guard let createdID = created["id"] as? String else {
                try await syncProjectTasksData(projectID: projectID)
                return
            }

            var updated = body
            updated["id"] = createdID
            updated["title"] = "[EQ] Updated \(iteration)"
            updated["description"] = "Earthquake update iteration \(iteration)."

            _ = try await apiClient.updateTask(taskID: createdID, body: updated)
            try await apiClient.deleteTask(taskID: createdID)
            try await syncProjectTasksData(projectID: projectID)
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
            edited["items"] = stressItemPayload(taskID: taskID, iteration: iteration)
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
            try await syncProjectTasksData(projectID: projectID)
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
            "items": stressItemPayload(taskID: taskID, iteration: iteration),
            "created_at": formatter.string(from: now),
            "updated_at": formatter.string(from: now)
        ]
    }

    private func stressItemPayload(taskID: String, iteration: Int) -> [[String: Any]] {
        [
            [
                "id": "\(taskID)-eq-\(iteration)-0",
                "title": "Earthquake step \(iteration)",
                "position": 0
            ],
            [
                "id": "\(taskID)-eq-\(iteration)-1",
                "title": "Verify overlap \(iteration)",
                "position": 1
            ]
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

    func syncProjects() async throws {
        try await runOperation("projects") {
            try await syncProjectsData()
        }
    }

    func syncProjectTasks(projectID: String) async throws {
        try await runOperation("projectTasks-\(projectID)") {
            try await syncProjectTasksData(projectID: projectID)
        }
    }

    func syncTaskDetail(taskID: String) async throws {
        try await runOperation("taskDetail-\(taskID)") {
            try await syncTaskDetailData(taskID: taskID)
        }
    }

    func syncTaskFormMetadata() async throws {
        try await runOperation("taskFormMetadata") {
            try await syncUsersData()
            try await syncTaskStatesData()
        }
    }

    func createTask(body: [String: Any], projectID: String) async throws {
        try await runOperation("createTask-\(projectID)") {
            let created = try await apiClient.createTask(body: body)
            try await syncProjectTasksData(projectID: projectID)
            if let createdID = created["id"] as? String {
                try await syncTaskDetailData(taskID: createdID)
            }
        }
    }

    func updateTask(taskID: String, projectID: String?, body: [String: Any]) async throws {
        try await runOperation("updateTask-\(taskID)") {
            _ = try await apiClient.updateTask(taskID: taskID, body: body)
            try await syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    func deleteTask(taskID: String, projectID: String) async throws {
        try await runOperation("deleteTask-\(taskID)") {
            try await apiClient.deleteTask(taskID: taskID)
            try await syncProjectTasksData(projectID: projectID)
        }
    }

    func replaceTaskReviewers(taskID: String, projectID: String?, reviewerIDs: [String]) async throws {
        try await runOperation("replaceTaskReviewers-\(taskID)") {
            _ = try await self.apiClient.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs)
            try await self.syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    func replaceTaskWatchers(taskID: String, projectID: String?, watcherIDs: [String]) async throws {
        try await runOperation("replaceTaskWatchers-\(taskID)") {
            _ = try await self.apiClient.replaceTaskWatchers(taskID: taskID, watcherIDs: watcherIDs)
            try await self.syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    private func syncProjectsData() async throws {
        let payload = try await apiClient.getProjects()
        try await syncContainer.sync(payload: payload, as: Project.self)
    }

    private func syncUsersData() async throws {
        let payload = try await apiClient.getUsers()
        try await syncContainer.sync(payload: payload, as: User.self)
    }

    private func syncTaskStatesData() async throws {
        let payload = try await apiClient.getTaskStateOptions()
        try await syncContainer.sync(payload: payload, as: TaskStateOption.self)
    }

    private func syncProjectTasksData(projectID: String) async throws {
        let payload = try await apiClient.getProjectTasks(projectID: projectID)

        if try project(withID: projectID) == nil {
            let projectsPayload = try await apiClient.getProjects()
            try await syncContainer.sync(payload: projectsPayload, as: Project.self)
        }

        guard let project = try project(withID: projectID) else { return }
        try await syncContainer.sync(payload: payload, as: Task.self, parent: project)
        try await syncProjectsData()
    }

    private func syncTaskDetailData(taskID: String) async throws {
        guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
        try await syncTaskDetailItem(payload)
        try await syncItemsIfPresent(in: payload, taskID: taskID)
    }

    private func syncTaskDetailItem(_ payload: [String: Any]) async throws {
        guard let projectID = payload["project_id"] as? String, !projectID.isEmpty else {
            throw SyncTaskDetailError.missingProjectID
        }
        guard let project = try project(withID: projectID) else {
            throw SyncTaskDetailError.missingProject(projectID)
        }
        try await syncContainer.sync(item: payload, as: Task.self, parent: project)
    }

    /// Canonical post-mutation sync sequence for a single task.
    /// Project list syncs first (broad refresh), task detail syncs last so its
    /// authoritative relationship payload always wins over any stale list snapshot.
    private func syncTaskAfterMutation(taskID: String, projectID: String?) async throws {
        if let projectID {
            try await syncProjectTasksData(projectID: projectID)
        }
        try await syncTaskDetailData(taskID: taskID)
    }

    private func runOperation(_ key: String, _ operation: () async throws -> Void) async throws {
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
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastErrorMessage = message
            throw error
        }
    }

    private func project(withID projectID: String) throws -> Project? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Project>()).first { $0.id == projectID }
    }

    private func taskForSync(withID taskID: String) throws -> Task? {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID })
        return try syncContainer.mainContext.fetch(descriptor).first
    }

    private func syncItemsIfPresent(in payload: [String: Any], taskID: String) async throws {
        guard let itemPayload = payload["items"] as? [[String: Any]] else { return }
        guard let task = try taskForSync(withID: taskID) else { return }
        try await syncContainer.sync(payload: itemPayload, as: Item.self, parent: task)
    }

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
