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

    /// When on, task create/edit/delete mutate the local store only — no network — and accumulate as
    /// pending changes until `pushPendingChanges()` reconciles them with the server.
    public var isOffline = false

    public private(set) var pendingChangeCount = 0

    /// Last point local state was reconciled with the server. Edits after this are pending updates;
    /// advanced after every inbound pull (so freshly-pulled rows aren't mistaken for local edits) and
    /// after a successful push.
    private var syncCursor = Date()

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
        if isOffline {
            guard try project(withID: projectID) != nil else {
                throw SyncTaskDetailError.missingProject(projectID)
            }
            try await syncContainer.sync(item: body, as: Task.self)
            refreshPendingCount()
            return
        }
        try await runOperation("createTask-\(projectID)") {
            let created = try await apiClient.createTask(body: body)
            try await syncProjectTasksData(projectID: projectID)
            if let createdID = created.string("id") {
                try await syncTaskDetailData(taskID: createdID)
            }
        }
    }

    public func updateTask(taskID: String, projectID: String?, body: DemoSyncPayload) async throws {
        if isOffline {
            try await syncContainer.sync(item: body, as: Task.self)
            if let task = try task(withID: taskID) {
                task.updatedAt = Date()
                try syncContainer.mainContext.save()
            }
            refreshPendingCount()
            return
        }
        try await runOperation("updateTask-\(taskID)") {
            _ = try await apiClient.updateTask(taskID: taskID, body: body)
            try await syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    public func deleteTask(taskID: String, projectID: String) async throws {
        if isOffline {
            if let task = try task(withID: taskID) {
                task.isLocallyDeleted = true
                task.updatedAt = Date()
                try syncContainer.mainContext.save()
            }
            refreshPendingCount()
            return
        }
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

    /// Push every locally-pending task change to the server and apply the result. Returns `nil` if a
    /// push is already in flight.
    @discardableResult
    public func pushPendingChanges() async throws -> SyncPushSummary? {
        let key = "push"
        guard !inFlightOperations.contains(key) else { return nil }

        inFlightOperations.insert(key)
        isSyncing = true
        defer {
            inFlightOperations.remove(key)
            isSyncing = !inFlightOperations.isEmpty
        }

        let summary = try await SwiftSync.push(
            for: Task.self,
            in: syncContainer.mainContext,
            changedSince: syncCursor,
            upload: { batch in try await self.upload(batch) }
        )
        syncCursor = summary.cursor
        refreshPendingCount()
        return summary
    }

    private func upload(_ batch: SyncPushBatch) async throws -> SyncPushResponse {
        var response = SyncPushResponse()
        for localID in batch.inserts {
            guard let body = try taskBody(localID: localID) else { continue }
            do {
                let created = try await apiClient.createTask(body: body)
                response.assignedRemoteIDs[localID] = created.string("id") ?? localID
            } catch {
                response.failures.append(
                    SyncPushFailure(localID: localID, operation: .insert, message: errorMessage(error)))
            }
        }
        for localID in batch.updates {
            guard let body = try taskBody(localID: localID) else { continue }
            do {
                _ = try await apiClient.updateTask(taskID: localID, body: body)
                response.confirmedUpdateLocalIDs.insert(localID)
            } catch {
                response.failures.append(
                    SyncPushFailure(localID: localID, operation: .update, message: errorMessage(error)))
            }
        }
        for localID in batch.deletes {
            do {
                try await apiClient.deleteTask(taskID: localID)
                response.confirmedDeleteLocalIDs.insert(localID)
            } catch {
                response.failures.append(
                    SyncPushFailure(localID: localID, operation: .delete, message: errorMessage(error)))
            }
        }
        return response
    }

    private func taskBody(localID: String) throws -> DemoSyncPayload? {
        guard let task = try task(withID: localID) else { return nil }
        return try DemoSyncPayload(dictionary: syncContainer.export(task))
    }

    private func refreshPendingCount() {
        let pending = try? SwiftSync.pendingChanges(
            for: Task.self, in: syncContainer.mainContext, changedSince: syncCursor)
        pendingChangeCount = pending.map { $0.inserts.count + $0.updates.count + $0.deletes.count } ?? 0
    }

    /// Mark every task the server just reported as synced (`syncRemoteID = id`) and advance the cursor,
    /// so freshly-pulled rows are not later mistaken for local inserts or edits.
    private func markServerTasksSynced(payloadIDs: [String]) throws {
        let idSet = Set(payloadIDs.filter { !$0.isEmpty })
        if !idSet.isEmpty {
            let tasks = try syncContainer.mainContext.fetch(FetchDescriptor<Task>())
            var changed = false
            for task in tasks where task.syncRemoteID == nil && idSet.contains(task.id) {
                task.syncRemoteID = task.id
                changed = true
            }
            if changed { try syncContainer.mainContext.save() }
        }
        syncCursor = Date()
        refreshPendingCount()
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        try markServerTasksSynced(payloadIDs: payload.compactMap { $0.string("id") })
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
        if let taskID = payload.string("id") {
            try markServerTasksSynced(payloadIDs: [taskID])
        }
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
