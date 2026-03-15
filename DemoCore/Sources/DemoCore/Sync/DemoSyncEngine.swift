import Foundation
import Observation
import SwiftData
@preconcurrency import SwiftSync

@MainActor
@Observable
public final class DemoSyncEngine {
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

    public private(set) var isSyncing = false

    private var inFlightOperations: Set<String> = []

    private let syncContainer: SyncContainer
    private let apiClient: FakeDemoAPIClient

    public init(syncContainer: SyncContainer, apiClient: FakeDemoAPIClient) {
        self.syncContainer = syncContainer
        self.apiClient = apiClient
    }

    public func syncProjects() async throws {
        try await runOperation("projects") {
            try await syncProjectsData()
        }
    }

    public func syncProjectTasks(projectID: String) async throws {
        try await runOperation("projectTasks-\(projectID)") {
            try await syncProjectTasksData(projectID: projectID)
        }
    }

    public func syncTaskDetail(taskID: String) async throws {
        try await runOperation("taskDetail-\(taskID)") {
            try await syncTaskDetailData(taskID: taskID)
        }
    }

    public func syncTaskFormMetadata() async throws {
        try await runOperation("taskFormMetadata") {
            try await syncUsersData()
            try await syncTaskStatesData()
        }
    }

    public func createTask(body: DemoSyncPayload, projectID: String) async throws {
        try await runOperation("createTask-\(projectID)") {
            let created = try await apiClient.createTask(body: body)
            try await syncProjectTasksData(projectID: projectID)
            if let createdID = created.string("id") {
                try await syncTaskDetailData(taskID: createdID)
            }
        }
    }

    public func updateTask(taskID: String, projectID: String?, body: DemoSyncPayload) async throws {
        try await runOperation("updateTask-\(taskID)") {
            _ = try await apiClient.updateTask(taskID: taskID, body: body)
            try await syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    public func deleteTask(taskID: String, projectID: String) async throws {
        try await runOperation("deleteTask-\(taskID)") {
            try await apiClient.deleteTask(taskID: taskID)
            try await syncProjectTasksData(projectID: projectID)
        }
    }

    public func replaceTaskReviewers(taskID: String, projectID: String?, reviewerIDs: [String]) async throws {
        try await runOperation("replaceTaskReviewers-\(taskID)") {
            _ = try await self.apiClient.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs)
            try await self.syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    public func replaceTaskWatchers(taskID: String, projectID: String?, watcherIDs: [String]) async throws {
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
        let userRowsBeforeSync = try localUserCount()

        if userRowsBeforeSync == 0 {
            try await syncUsersData()
        }

        if try project(withID: projectID) == nil {
            let projectsPayload = try await apiClient.getProjects()
            try await syncContainer.sync(payload: projectsPayload, as: Project.self)
        }
        guard let resolvedProject = try project(withID: projectID) else { return }
        nonisolated(unsafe) let project = resolvedProject
        try await syncContainer.sync(
            payload: payload,
            as: Task.self,
            parent: project,
            relationship: \Task.project
        )
        try await syncProjectsData()
    }

    private func syncTaskDetailData(taskID: String) async throws {
        guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
        let userRowsBeforeSync = try localUserCount()

        if userRowsBeforeSync == 0 {
            try await syncUsersData()
        }

        try await syncTaskDetailItem(payload)
        try await syncItemsIfPresent(in: payload, taskID: taskID)
    }

    private func syncTaskDetailItem(_ payload: DemoSyncPayload) async throws {
        guard let projectID = payload.string("project_id"), !projectID.isEmpty else {
            throw SyncTaskDetailError.missingProjectID
        }
        guard try project(withID: projectID) != nil else {
            throw SyncTaskDetailError.missingProject(projectID)
        }
        try await syncContainer.sync(item: payload, as: Task.self)
    }

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

        try await operation()
    }

    private func project(withID projectID: String) throws -> Project? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Project>()).first { $0.id == projectID }
    }

    private func task(withID taskID: String) throws -> Task? {
        try syncContainer.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID })
        ).first
    }

    private func syncItemsIfPresent(in payload: DemoSyncPayload, taskID: String) async throws {
        guard let itemPayload = payload.objectArray("items") else { return }
        guard let resolvedTask = try task(withID: taskID) else { return }
        nonisolated(unsafe) let task = resolvedTask
        try await syncContainer.sync(
            payload: itemPayload,
            as: Item.self,
            parent: task,
            relationship: \Item.task
        )
    }

    private func localUserCount() throws -> Int {
        try syncContainer.mainContext.fetch(FetchDescriptor<User>()).count
    }
}
