import Combine
import Foundation
import SwiftData
import SwiftSync

@MainActor
final class DemoSyncEngine: ObservableObject {
    enum OperationResult: Equatable {
        case success
        case failure(String)
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSyncDate: Date?

    private(set) var hasBootstrapped = false
    private var inFlightOperations: Set<String> = []

    private let syncContainer: SyncContainer
    private let apiClient: DemoAPIClient

    init(syncContainer: SyncContainer, apiClient: DemoAPIClient) {
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
            try await syncTagsInternal()
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

    func syncTags() async {
        await syncOperation("tags") {
            try await syncTagsInternal()
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

    func syncTaskComments(taskID: String) async {
        await syncOperation("taskComments-\(taskID)") {
            try await syncTaskCommentsInternal(taskID: taskID)
        }
    }

    func syncTagTasks(tagID: String) async {
        await syncOperation("tagTasks-\(tagID)") {
            try await syncTagTasksInternal(tagID: tagID)
        }
    }

    @discardableResult
    func createTask(
        projectID: String,
        title: String,
        descriptionText: String,
        state: String,
        assigneeID: String?,
        tagIDs: [String]
    ) async -> OperationResult {
        await syncOperationResult("createTask-\(projectID)") {
            _ = try await apiClient.createTask(
                projectID: projectID,
                title: title,
                descriptionText: descriptionText,
                state: state,
                assigneeID: assigneeID,
                tagIDs: tagIDs
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

    @discardableResult
    func updateTaskDescription(taskID: String, projectID: String?, descriptionText: String) async -> OperationResult {
        await syncOperationResult("patchTaskDescription-\(taskID)") {
            _ = try await apiClient.patchTaskDescription(taskID: taskID, descriptionText: descriptionText)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    @discardableResult
    func updateTaskState(taskID: String, projectID: String?, state: String) async -> OperationResult {
        await syncOperationResult("patchTaskState-\(taskID)") {
            _ = try await apiClient.patchTaskState(taskID: taskID, state: state)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    @discardableResult
    func updateTaskAssignee(taskID: String, projectID: String?, assigneeID: String?) async -> OperationResult {
        await syncOperationResult("patchTaskAssignee-\(taskID)") {
            _ = try await apiClient.patchTaskAssignee(taskID: taskID, assigneeID: assigneeID)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    @discardableResult
    func replaceTaskTags(taskID: String, projectID: String?, tagIDs: [String]) async -> OperationResult {
        await syncOperationResult("replaceTaskTags-\(taskID)") {
            _ = try await apiClient.replaceTaskTags(taskID: taskID, tagIDs: tagIDs)
            try await syncTaskDetailInternal(taskID: taskID)
            if let projectID {
                try await syncProjectTasksInternal(projectID: projectID)
            }
        }
    }

    @discardableResult
    func createComment(taskID: String, authorUserID: String, body: String) async -> OperationResult {
        await syncOperationResult("createComment-\(taskID)") {
            _ = try await apiClient.createTaskComment(taskID: taskID, authorUserID: authorUserID, body: body)
            try await syncTaskCommentsInternal(taskID: taskID)
        }
    }

    func deleteComment(commentID: String, taskID: String) async {
        await syncOperation("deleteComment-\(commentID)") {
            try await apiClient.deleteTaskComment(commentID: commentID)
            try await syncTaskCommentsInternal(taskID: taskID)
        }
    }

    private func syncProjectsInternal() async throws {
        let payload = try await apiClient.getProjects()
        try await syncPayload(payload, as: Project.self, missingRowPolicy: .delete)
    }

    private func syncUsersInternal() async throws {
        let payload = try await apiClient.getUsers()
        try await syncPayload(payload, as: User.self, missingRowPolicy: .delete)
    }

    private func syncTagsInternal() async throws {
        let payload = try await apiClient.getTags()
        try await syncPayload(payload, as: Tag.self, missingRowPolicy: .delete)
    }

    private func syncProjectTasksInternal(projectID: String) async throws {
        let payload = try await apiClient.getProjectTasks(projectID: projectID)

        if try project(withID: projectID) == nil {
            let projectsPayload = try await apiClient.getProjects()
            try await syncPayload(projectsPayload, as: Project.self, missingRowPolicy: .delete)
        }

        guard let project = try project(withID: projectID) else { return }
        try await syncPayload(payload, as: Task.self, parent: project, missingRowPolicy: .delete)
        try await syncProjectsInternal()
    }

    private func syncTaskDetailInternal(taskID: String) async throws {
        guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
        try await syncPayload([payload], as: Task.self, missingRowPolicy: .keep)
    }

    private func syncTaskCommentsInternal(taskID: String) async throws {
        let payload = try await apiClient.getTaskComments(taskID: taskID)

        if try task(withID: taskID) == nil {
            try await syncTaskDetailInternal(taskID: taskID)
        }

        guard let task = try task(withID: taskID) else { return }
        try await syncPayload(payload, as: Comment.self, parent: task, missingRowPolicy: .delete)
    }

    private func syncTagTasksInternal(tagID: String) async throws {
        let payload = try await apiClient.getTagTasks(tagID: tagID)
        try await syncPayload(payload, as: Task.self, missingRowPolicy: .keep)
    }

    private func syncOperation(_ key: String, _ operation: () async throws -> Void) async {
        _ = await syncOperationResult(key, operation)
    }

    private func syncOperationResult(_ key: String, _ operation: () async throws -> Void) async -> OperationResult {
        guard !inFlightOperations.contains(key) else { return .success }

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
            return .success
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastErrorMessage = message
            return .failure(message)
        }
    }

    private func syncPayload<Model: SyncUpdatableModel>(
        _ payload: [[String: Any]],
        as model: Model.Type,
        missingRowPolicy: SyncMissingRowPolicy
    ) async throws {
        try await syncContainer.sync(
            payload: payload,
            as: model,
            missingRowPolicy: missingRowPolicy
        )
    }

    private func syncPayload<Model: SyncUpdatableModel, Parent: PersistentModel>(
        _ payload: [[String: Any]],
        as model: Model.Type,
        parent: Parent,
        missingRowPolicy: SyncMissingRowPolicy
    ) async throws {
        try await syncContainer.sync(
            payload: payload,
            as: model,
            parent: parent,
            missingRowPolicy: missingRowPolicy
        )
    }

    private func project(withID projectID: String) throws -> Project? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Project>()).first { $0.id == projectID }
    }

    private func task(withID taskID: String) throws -> Task? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).first { $0.id == taskID }
    }
}
