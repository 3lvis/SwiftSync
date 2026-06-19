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
            case .missingProject(let projectID):
                return "Task detail sync requires project \(projectID) to exist locally."
            }
        }
    }

    public private(set) var isSyncing = false

    /// Simulated airplane mode. The state lives at the transport (`apiClient`); this mirror drives it
    /// and lets the UI bind to it. While offline, pulls keep serving the local cache, task edits queue
    /// locally, and push is held — reconciled on reconnect.
    public var isOffline = false {
        didSet { apiClient.isOffline = isOffline }
    }

    public private(set) var pendingChangeCount = 0

    /// Rows the server rejected (a failure reason is set). Drives the failures inbox.
    public private(set) var failedChangeCount = 0

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
        try await pull("projects") {
            try await self.syncProjectsData()
        }
    }

    public func syncProjectTasks(projectID: String) async throws {
        try await pull("projectTasks-\(projectID)") {
            try await self.syncProjectTasksData(projectID: projectID)
        }
    }

    public func syncTaskDetail(taskID: String) async throws {
        try await pull("taskDetail-\(taskID)") {
            try await self.syncTaskDetailData(taskID: taskID)
        }
    }

    public func syncTaskFormMetadata() async throws {
        try await pull("taskFormMetadata") {
            try await self.syncUsersData()
            try await self.syncTaskStatesData()
        }
    }

    /// Run an inbound pull, tolerating a dead transport: while offline the refresh is skipped and the
    /// UI keeps reading the local cache (a failed refresh is a non-event, never a surfaced error).
    private func pull(_ key: String, _ operation: () async throws -> Void) async throws {
        do {
            try await runOperation(key, operation)
        } catch DemoAPIError.offline {
            // Offline: keep serving what's already in the local store.
        }
    }

    public func createTask(body: DemoSyncPayload, projectID: String) async throws {
        if isOffline {
            guard try project(withID: projectID) != nil else {
                throw SyncTaskDetailError.missingProject(projectID)
            }
            try await syncContainer.sync(item: body, as: Task.self, context: .main)
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
        // A row the server doesn't have yet (offline-created, or a rejected insert) can't be PUT — it
        // must be re-inserted. Apply locally so it stays a pending insert; online, push to (re)insert.
        let neverSynced = (try task(withID: taskID))?.syncRemoteID == nil
        if isOffline || neverSynced {
            try await syncContainer.sync(item: body, as: Task.self, context: .main)
            if let task = try task(withID: taskID) {
                task.updatedAt = Date()
                task.syncFailureReason = nil  // the corrected edit gets a fresh attempt
                try syncContainer.mainContext.save()
            }
            refreshPendingCount()
            if !isOffline {
                _ = try await pushPendingChanges()
            }
            return
        }
        try await runOperation("updateTask-\(taskID)") {
            _ = try await apiClient.updateTask(taskID: taskID, body: body)
            try await syncTaskAfterMutation(taskID: taskID, projectID: projectID)
            // A successful online edit resolves any prior failure on this row (e.g. fixing a rejected
            // offline edit from the failures inbox). syncFailureReason is @NotExport, so the server
            // refresh won't clear it — do it explicitly.
            if let task = try task(withID: taskID), task.syncFailureReason != nil {
                task.syncFailureReason = nil
                try syncContainer.mainContext.save()
                refreshPendingCount()
            }
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
        if isOffline {
            try applyLocalPeople(taskID: taskID, reviewerIDs: reviewerIDs)
            return
        }
        try await runOperation("replaceTaskReviewers-\(taskID)") {
            _ = try await self.apiClient.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs)
            try await self.syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    public func replaceTaskWatchers(taskID: String, projectID: String?, watcherIDs: [String]) async throws {
        if isOffline {
            try applyLocalPeople(taskID: taskID, watcherIDs: watcherIDs)
            return
        }
        try await runOperation("replaceTaskWatchers-\(taskID)") {
            _ = try await self.apiClient.replaceTaskWatchers(taskID: taskID, watcherIDs: watcherIDs)
            try await self.syncTaskAfterMutation(taskID: taskID, projectID: projectID)
        }
    }

    /// Apply a reviewers/watchers change to the local store only (offline). The bumped `updatedAt`
    /// makes it a pending update; the push carries `reviewer_ids`/`watcher_ids` so the server applies it.
    private func applyLocalPeople(taskID: String, reviewerIDs: [String]? = nil, watcherIDs: [String]? = nil)
        throws
    {
        guard let task = try task(withID: taskID) else { return }
        if let reviewerIDs { task.reviewers = try users(for: reviewerIDs) }
        if let watcherIDs { task.watchers = try users(for: watcherIDs) }
        task.updatedAt = Date()
        try syncContainer.mainContext.save()
        refreshPendingCount()
    }

    private func users(for ids: [String]) throws -> [User] {
        let byID = Dictionary(
            uniqueKeysWithValues: try syncContainer.mainContext.fetch(FetchDescriptor<User>()).map {
                ($0.id, $0)
            })
        return ids.compactMap { byID[$0] }
    }

    /// Push every locally-pending task change to the server and apply the result. Returns `nil` while
    /// offline (no network) or if a push is already in flight.
    @discardableResult
    public func pushPendingChanges() async throws -> SyncPushSummary? {
        guard !isOffline else { return nil }
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

    /// Serialize the pending batch into the `/sync/upload` operation list, POST it once, and map the
    /// per-operation results back into a `SyncPushResponse`. Every created-or-edited row is an `upsert`
    /// keyed by its stable `localId` (the server find-by-localId → update-else-creates, minting and
    /// returning a distinct `remoteId` on first create); tombstones are a `delete` by the same
    /// `localId`. A `stale` result means the server won last-writer-wins — adopt its state locally and
    /// treat the row as resolved so it isn't re-sent.
    private func upload(_ batch: SyncPushBatch) async throws -> SyncPushResponse {
        var operations: [[String: Any]] = []

        for localID in batch.inserts + batch.updates {
            guard let task = try task(withID: localID) else { continue }
            let data = taskData(task)
            operations.append([
                "operation": "upsert", "type": "tasks", "localId": localID,
                "updatedAt": data["updated_at"] ?? "", "data": data,
            ])
        }
        for localID in batch.deletes {
            guard let task = try task(withID: localID) else { continue }
            let data = syncContainer.export(task)
            operations.append([
                "operation": "delete", "type": "tasks", "localId": localID,
                "updatedAt": data["updated_at"] ?? "",
            ])
        }

        let results = try await apiClient.upload(operations: operations)

        var response = SyncPushResponse()
        for result in results {
            let operation = result["operation"] as? String
            let status = result["status"] as? String
            let localID = result["localId"] as? String
            let remoteID = result["remoteId"] as? String
            switch (operation, status) {
            case ("upsert", "applied"), ("upsert", "stale"):
                // An applied upsert resolves both inserts (stamp the server-minted remoteId) and
                // updates; SwiftSync scopes each field to its own batch slice, so populating both is
                // safe.
                if let localID, let remoteID { response.assignedRemoteIDs[localID] = remoteID }
                if let localID { response.confirmedUpdateLocalIDs.insert(localID) }
                if status == "stale", let server = result["server"] as? [String: Any] {
                    try? await syncContainer.sync(
                        item: DemoSyncPayload(dictionary: server), as: Task.self, context: .main)
                }
            case ("delete", "applied"):
                if let localID { response.confirmedDeleteLocalIDs.insert(localID) }
            case ("delete", "stale"):
                // The server has a newer edit — the delete lost LWW. Abandon the tombstone and adopt
                // the server's state so the row reappears with the winning version (no re-send loop).
                if let localID, let server = result["server"] as? [String: Any] {
                    try? await syncContainer.sync(
                        item: DemoSyncPayload(dictionary: server), as: Task.self, context: .main)
                    if let task = try task(withID: localID) { task.isLocallyDeleted = false }
                }
            default:
                response.failures.append(
                    SyncPushFailure(
                        localID: localID ?? "",
                        operation: operation == "delete" ? .delete : .update,
                        message: (result["message"] as? String) ?? "rejected"))
            }
        }
        return response
    }

    /// The task's upload payload: its exported scalars plus `reviewer_ids`/`watcher_ids` (which are
    /// `@NotExport`, so `export` omits them) so relationship edits travel with the operation.
    private func taskData(_ task: Task) -> [String: Any] {
        var data = syncContainer.export(task)
        data["reviewer_ids"] = task.reviewers.map(\.id)
        data["watcher_ids"] = task.watchers.map(\.id)
        return data
    }

    private func refreshPendingCount() {
        let pending = try? SwiftSync.pendingChanges(
            for: Task.self, in: syncContainer.mainContext, changedSince: syncCursor)
        pendingChangeCount = pending.map { $0.inserts.count + $0.updates.count + $0.deletes.count } ?? 0

        let failed = try? syncContainer.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { $0.syncFailureReason != nil }))
        failedChangeCount = failed?.count ?? 0
    }

    /// Tasks the server rejected (a failure reason is set), newest first — the failures inbox.
    public func failedTasks() -> [Task] {
        (try? syncContainer.mainContext.fetch(
            FetchDescriptor<Task>(
                predicate: #Predicate { $0.syncFailureReason != nil },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
    }

    /// Resolve a rejected change: drop a never-synced row, or restore the server's version of an
    /// edited row (abandoning the local edit) and clear its failure.
    public func discardFailedChange(taskID: String) async throws {
        guard let task = try task(withID: taskID) else { return }
        if task.syncRemoteID == nil {
            syncContainer.mainContext.delete(task)
            try syncContainer.mainContext.save()
        } else {
            try await syncTaskDetail(taskID: taskID)
            if let refreshed = try self.task(withID: taskID) {
                refreshed.syncFailureReason = nil
                try syncContainer.mainContext.save()
            }
        }
        refreshPendingCount()
    }

    /// After an inbound pull, advance the cursor so freshly-pulled rows aren't mistaken for local
    /// edits, and refresh the pending count. (`syncRemoteID` is populated from `remote_id` on import.)
    private func markPulled() {
        syncCursor = Date()
        refreshPendingCount()
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
        // Push before pull: a pending change must reach the server before the pull's prune judges it,
        // else it looks like a server-side deletion. Best-effort — a failed drain must not block the refresh.
        _ = try? await pushPendingChanges()

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
        markPulled()
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
        try await syncContainer.sync(item: payload, as: Task.self, context: .background)
        markPulled()
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
