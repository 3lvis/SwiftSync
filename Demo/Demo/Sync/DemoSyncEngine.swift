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
            let body = try Self.buildCreateTaskBody(
                projectID: projectID,
                title: title,
                descriptionText: descriptionText,
                state: state,
                assigneeID: assigneeID,
                authorID: authorID
            )
            _ = try await apiClient.createTask(body: body)
            try await syncProjectTasksInternal(projectID: projectID)
        }
    }

    /// Builds the JSON create-body for a new Task by inserting a transient Task into a
    /// temporary in-memory ModelContext and exporting it with SwiftSync's export system.
    /// The client is the authority for id, created_at, and updated_at on creation.
    private static func buildCreateTaskBody(
        projectID: String,
        title: String,
        descriptionText: String,
        state: String,
        assigneeID: String?,
        authorID: String
    ) throws -> [String: Any] {
        let schema = Schema([Task.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let now = Date()
        let task = Task(
            id: UUID().uuidString,
            projectID: projectID,
            assigneeID: assigneeID,
            authorID: authorID,
            title: title,
            descriptionText: descriptionText,
            state: state,
            stateLabel: "",
            createdAt: now,
            updatedAt: now
        )
        context.insert(task)

        var exportState = ExportState()
        let options = ExportOptions(relationshipMode: .none, includeNulls: false)
        return task.exportObject(using: options, state: &exportState)
    }

    /// Builds the JSON update-body for an existing Task using the same export-based pattern as
    /// buildCreateTaskBody: a transient Task is populated with the full set of field values and
    /// exported via SwiftSync's export system so that @RemoteKey, @RemotePath, and snake_case
    /// transforms are applied consistently. stateLabel is left empty because the server resolves
    /// the label from the state id; it is not part of the PUT contract.
    private static func buildUpdateTaskBody(
        taskID: String,
        projectID: String,
        title: String,
        descriptionText: String,
        state: String,
        assigneeID: String?,
        authorID: String,
        createdAt: Date,
        updatedAt: Date
    ) throws -> [String: Any] {
        let schema = Schema([Task.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let task = Task(
            id: taskID,
            projectID: projectID,
            assigneeID: assigneeID,
            authorID: authorID,
            title: title,
            descriptionText: descriptionText,
            state: state,
            stateLabel: "",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        context.insert(task)

        var exportState = ExportState()
        let options = ExportOptions(relationshipMode: .none, includeNulls: false)
        return task.exportObject(using: options, state: &exportState)
    }

    func deleteTask(taskID: String, projectID: String) async {
        await syncOperation("deleteTask-\(taskID)") {
            try await apiClient.deleteTask(taskID: taskID)
            try await syncProjectTasksInternal(projectID: projectID)
        }
    }

    func updateTaskDescription(taskID: String, projectID: String?, descriptionText: String) async throws {
        try await updateTask(taskID: taskID, projectID: projectID, descriptionText: descriptionText)
    }

    func updateTaskState(taskID: String, projectID: String?, state: String) async throws {
        try await updateTask(taskID: taskID, projectID: projectID, state: state)
    }

    func updateTaskAssignee(taskID: String, projectID: String?, assigneeID: String?) async throws {
        try await updateTask(taskID: taskID, projectID: projectID, assigneeID: assigneeID)
    }

    /// Sends a full PUT update for a task, building the request body via SwiftSync's export system
    /// so that @RemoteKey and @RemotePath field mappings are applied consistently with createTask.
    /// Only the provided non-nil overrides are applied; all other fields are read from the local store.
    private func updateTask(
        taskID: String,
        projectID: String?,
        title: String? = nil,
        descriptionText: String? = nil,
        state: String? = nil,
        assigneeID: String?? = nil
    ) async throws {
        try await syncOperationThrowing("updateTask-\(taskID)") {
            guard let current = try self.task(withID: taskID) else { return }

            let body = try Self.buildUpdateTaskBody(
                taskID: current.id,
                projectID: current.projectID,
                title: title ?? current.title,
                descriptionText: descriptionText ?? current.descriptionText,
                state: state ?? current.state,
                assigneeID: assigneeID ?? current.assigneeID,
                authorID: current.authorID,
                createdAt: current.createdAt,
                updatedAt: current.updatedAt
            )
            _ = try await apiClient.updateTask(taskID: taskID, body: body)
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

    private func task(withID taskID: String) throws -> Task? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).first { $0.id == taskID }
    }
}
