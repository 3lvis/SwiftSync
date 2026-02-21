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

    func syncUserTasks(userID: String) async {
        await syncOperation("userTasks-\(userID)") {
            let payload = try await apiClient.getUserTasks(userID: userID)
            try await mergePayload(payload, as: Task.self)
        }
    }

    func syncTaskDetail(taskID: String) async {
        await syncOperation("taskDetail-\(taskID)") {
            guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
            try await mergePayload([payload], as: Task.self)
        }
    }

    func syncTaskComments(taskID: String) async {
        await syncOperation("taskComments-\(taskID)") {
            let payload = try await apiClient.getTaskComments(taskID: taskID)

            if try task(withID: taskID) == nil {
                if let detailPayload = try await apiClient.getTaskDetail(taskID: taskID) {
                    try await mergePayload([detailPayload], as: Task.self)
                }
            }

            guard let task = try task(withID: taskID) else { return }
            try await mergePayload(payload, as: Comment.self, parent: task)
        }
    }

    func syncTagTasks(tagID: String) async {
        await syncOperation("tagTasks-\(tagID)") {
            let payload = try await apiClient.getTagTasks(tagID: tagID)
            try await mergePayload(payload, as: Task.self)
        }
    }

    private func syncProjectsInternal() async throws {
        let payload = try await apiClient.getProjects()
        try await replacePayload(payload, as: Project.self)
    }

    private func syncUsersInternal() async throws {
        let payload = try await apiClient.getUsers()
        try await replacePayload(payload, as: User.self)
    }

    private func syncTagsInternal() async throws {
        let payload = try await apiClient.getTags()
        try await replacePayload(payload, as: Tag.self)
    }

    private func syncProjectTasksInternal(projectID: String) async throws {
        let payload = try await apiClient.getProjectTasks(projectID: projectID)

        if try project(withID: projectID) == nil {
            let projectsPayload = try await apiClient.getProjects()
            try await replacePayload(projectsPayload, as: Project.self)
        }

        guard let project = try project(withID: projectID) else { return }
        try await replacePayload(payload, as: Task.self, parent: project)
    }

    private func syncOperation(_ key: String, _ operation: () async throws -> Void) async {
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
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func replacePayload<Model: SyncUpdatableModel>(
        _ payload: [[String: Any]],
        as model: Model.Type
    ) async throws {
        let context = syncContainer.makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            missingRowPolicy: .delete
        )
    }

    private func mergePayload<Model: SyncUpdatableModel>(
        _ payload: [[String: Any]],
        as model: Model.Type
    ) async throws {
        let context = syncContainer.makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            missingRowPolicy: .keep
        )
    }

    private func replacePayload<Model: ParentScopedModel>(
        _ payload: [[String: Any]],
        as model: Model.Type,
        parent: Model.SyncParent
    ) async throws {
        let context = syncContainer.makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            parent: parent,
            missingRowPolicy: .delete
        )
    }

    private func mergePayload<Model: ParentScopedModel>(
        _ payload: [[String: Any]],
        as model: Model.Type,
        parent: Model.SyncParent
    ) async throws {
        let context = syncContainer.makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            parent: parent,
            missingRowPolicy: .keep
        )
    }

    private func project(withID projectID: String) throws -> Project? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Project>()).first { $0.id == projectID }
    }

    private func task(withID taskID: String) throws -> Task? {
        try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).first { $0.id == taskID }
    }
}
