import Combine
import Foundation
import SwiftData
import SwiftSync

@MainActor
final class DemoSyncEngine: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSyncDate: Date?

    private(set) var hasBootstrapped = false
    private var inFlightOperations: Set<String> = []

    private let syncContainer: SyncContainer
    private let apiClient: FakeDemoAPIClient

    init(syncContainer: SyncContainer, apiClient: FakeDemoAPIClient) {
        self.syncContainer = syncContainer
        self.apiClient = apiClient
    }

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

    func syncTaskDetail(taskID: String) async {
        await syncOperation("taskDetail-\(taskID)") {
            try await syncTaskDetailInternal(taskID: taskID)
        }
    }

    func createTask(
        projectID: String,
        title: String,
        descriptionText: String,
        state: String,
        assigneeID: String?,
        authorID: String
    ) async throws {
        try await syncOperationThrowing("createTask-\(projectID)") {
            _ = try await apiClient.createTask(
                projectID: projectID,
                title: title,
                descriptionText: descriptionText,
                state: state,
                assigneeID: assigneeID,
                authorID: authorID
            )
            try await syncProjectTasksInternal(projectID: projectID)
        }
    }

    func deleteTask(taskID: String, projectID: String) async {
        await syncOperation("deleteTask-\(taskID)") {
            try await apiClient.deleteTask(taskID: taskID)
            try await syncProjectTasksInternal(projectID: projectID)
        }
    }

    func updateTaskDescription(taskID: String, projectID: String?, descriptionText: String) async throws {
        try await syncOperationThrowing("patchTaskDescription-\(taskID)") {
            _ = try await apiClient.patchTaskDescription(taskID: taskID, descriptionText: descriptionText)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    func updateTaskState(taskID: String, projectID: String?, state: String) async throws {
        try await syncOperationThrowing("patchTaskState-\(taskID)") {
            _ = try await apiClient.patchTaskState(taskID: taskID, state: state)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    func updateTaskAssignee(taskID: String, projectID: String?, assigneeID: String?) async throws {
        try await syncOperationThrowing("patchTaskAssignee-\(taskID)") {
            _ = try await apiClient.patchTaskAssignee(taskID: taskID, assigneeID: assigneeID)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    func replaceTaskReviewers(taskID: String, projectID: String?, reviewerIDs: [String]) async throws {
        try await syncOperationThrowing("replaceTaskReviewers-\(taskID)") {
            _ = try await apiClient.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    func replaceTaskWatchers(taskID: String, projectID: String?, watcherIDs: [String]) async throws {
        try await syncOperationThrowing("replaceTaskWatchers-\(taskID)") {
            _ = try await apiClient.replaceTaskWatchers(taskID: taskID, watcherIDs: watcherIDs)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    private func syncProjectsInternal() async throws {
        let payload = try await apiClient.getProjects()
        try await syncContainer.sync(payload: payload, as: Project.self)
    }

    private func syncUsersInternal() async throws {
        let payload = try await apiClient.getUsers()
        try await syncContainer.sync(payload: payload, as: User.self)
    }

    private func syncTaskStatesInternal() async throws {
        let payload = try await apiClient.getTaskStateOptions()
        try await syncContainer.sync(payload: payload, as: TaskStateOption.self)
    }

    private func syncUserRolesInternal() async throws {
        let payload = try await apiClient.getUserRoleOptions()
        try await syncContainer.sync(payload: payload, as: UserRoleOption.self)
    }

    private func syncProjectTasksInternal(projectID: String) async throws {
        let payload = try await apiClient.getProjectTasks(projectID: projectID)

        if try project(withID: projectID) == nil {
            let projectsPayload = try await apiClient.getProjects()
            try await syncContainer.sync(payload: projectsPayload, as: Project.self)
        }

        guard let project = try project(withID: projectID) else { return }
        try await syncContainer.sync(payload: payload, as: Task.self, parent: project)
        try await syncProjectsInternal()
    }

    private func syncTaskDetailInternal(taskID: String) async throws {
        guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
        try await syncContainer.sync(item: payload, as: Task.self)
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
}
