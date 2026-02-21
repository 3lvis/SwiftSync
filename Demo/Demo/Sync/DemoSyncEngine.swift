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
            try await syncPayload(payload, as: Task.self, missingRowPolicy: .keep)
        }
    }

    func syncTaskDetail(taskID: String) async {
        await syncOperation("taskDetail-\(taskID)") {
            guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
            try await syncPayload([payload], as: Task.self, missingRowPolicy: .keep)
        }
    }

    func syncTaskComments(taskID: String) async {
        await syncOperation("taskComments-\(taskID)") {
            let payload = try await apiClient.getTaskComments(taskID: taskID)

            if try task(withID: taskID) == nil {
                if let detailPayload = try await apiClient.getTaskDetail(taskID: taskID) {
                    try await syncPayload([detailPayload], as: Task.self, missingRowPolicy: .keep)
                }
            }

            guard let task = try task(withID: taskID) else { return }
            try await syncPayload(payload, as: Comment.self, parent: task, missingRowPolicy: .keep)
        }
    }

    func syncTagTasks(tagID: String) async {
        await syncOperation("tagTasks-\(tagID)") {
            let payload = try await apiClient.getTagTasks(tagID: tagID)
            try await syncPayload(payload, as: Task.self, missingRowPolicy: .keep)
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
