import Foundation
import Observation
import SwiftData
@preconcurrency import SwiftSync

public struct DemoUploadRejection: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

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

    /// Simulated airplane mode the UI binds to. Flipping back online drains the offline queue.
    public var isOffline = false {
        didSet {
            apiClient.isOffline = isOffline
            if !isOffline && oldValue {
                _Concurrency.Task { try? await pushPendingChanges() }
            }
        }
    }

    public private(set) var pendingChangeCount = 0

    /// Rows the server rejected (a failure reason is set). Drives the failures inbox.
    public private(set) var failedChangeCount = 0

    private var inFlightOperations: Set<String> = []
    /// The drain in progress, if any — concurrent pushes (reconnect + push-before-pull) coalesce onto it.
    private var activeDrain: _Concurrency.Task<[SyncPendingChangesFailure], Error>?

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

    public func createTask(body: SyncJSON, projectID: String) async throws {
        if isOffline {
            guard let project = try project(withID: projectID) else {
                throw SyncTaskDetailError.missingProject(projectID)
            }
            try applyLocalTask(body, project: project)
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

    public func updateTask(taskID: String, projectID: String?, body: SyncJSON) async throws {
        // A row the server doesn't have yet (offline-created, or a rejected insert) can't be PUT — it
        // must be (re)sent as an upsert. Apply locally so it stays a pending change; online, push it.
        let neverSynced = isNeverPushed(taskID)
        if isOffline || neverSynced {
            try applyLocalTask(body)
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
            // Hard-delete locally: the row leaves the UI at once, and its id survives in store history
            // (identity is .preserveValueOnDeletion) so the deletion is recovered and pushed later.
            if let task = try task(withID: taskID) {
                syncContainer.mainContext.delete(task)
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

    /// Drain the pending task changes to the server and stamp any rejections on the failures inbox.
    /// SwiftSync brackets the storage token; the `upload` closure is the networking half.
    @discardableResult
    public func pushPendingChanges() async throws -> [SyncPendingChangesFailure]? {
        guard !isOffline else { return nil }
        // Coalesce onto a running drain: it converges (re-reads the pending set after every upload), so a
        // caller that joins — a concurrent push-before-pull, or an edit landing mid-drain — is covered by
        // a later pass and never stranded on a stale snapshot.
        if let activeDrain { return try await activeDrain.value }

        let task = _Concurrency.Task { @MainActor in try await self.drainToConvergence() }
        activeDrain = task
        defer { activeDrain = nil }
        isSyncing = true
        defer { isSyncing = !inFlightOperations.isEmpty }
        return try await task.value
    }

    /// Upload pending changes pass by pass until the queue is empty, re-reading the pending set after each
    /// pass. The history token advances only on a clean pass, so an edit that lands mid-upload stays
    /// pending and is picked up by the next pass instead of being stranded (the P1 strand).
    ///
    /// Stops on a pass that leaves failures: a rejected row pins the token (`withPendingChanges` won't
    /// advance past it), so nothing more can drain until the user resolves it — looping would spin. A
    /// throw (transport/server error) propagates without annotating, leaving the inbox intact — only a
    /// completed pass re-stamps `syncFailureReason`.
    private func drainToConvergence() async throws -> [SyncPendingChangesFailure] {
        var lastFailures: [SyncPendingChangesFailure] = []
        repeat {
            lastFailures = try await SwiftSync.withPendingChanges(for: Task.self, in: syncContainer.mainContext) {
                pending in try await self.upload(pending)
            }
            try annotateFailures(lastFailures)
            refreshPendingCount()
        } while !isOffline && lastFailures.isEmpty && pendingChangeCount > 0
        return lastFailures
    }

    /// Serialize the pending batch into the `/sync/upload` operation list, POST it once, and return only
    /// the per-row failures — SwiftSync confirms everything else by complement. Every created-or-edited
    /// row is an `upsert` keyed by its stable `id` (the server find-by-id → update-else-creates, adopting
    /// that `id` as the row's `public_id` — no distinct server id comes back); tombstones are a `delete`
    /// by the same `id`. A `stale` result means the server won last-writer-wins — adopt its state locally
    /// and treat the row as resolved (not a failure) so it isn't re-sent.
    private func upload(_ pending: SyncPendingChanges) async throws -> [SyncPendingChangesFailure] {
        var operations: [[String: Any]] = []

        for id in pending.inserts + pending.updates {
            guard let task = try task(withID: id) else { continue }
            let data = taskData(task)
            operations.append([
                "operation": "upsert", "type": "tasks", "id": id,
                "updatedAt": data["updated_at"] ?? "", "data": data,
            ])
        }
        for id in pending.deletes {
            // The row is already hard-deleted locally — its id is recovered from store history — so the
            // delete can't fetch the gone task. Stamp the deletion time now for the server's LWW check.
            operations.append([
                "operation": "delete", "type": "tasks", "id": id,
                "updatedAt": syncContainer.dateFormatter.string(from: Date()),
            ])
        }

        let results = try await apiClient.upload(operations: operations)

        var failures: [SyncPendingChangesFailure] = []
        for result in results {
            let operation = result["operation"] as? String
            let status = result["status"] as? String
            let id = result["id"] as? String
            switch (operation, status) {
            case ("upsert", "stale"), ("delete", "stale"):
                // The server won last-writer-wins — adopt its state locally (the inbound sync re-creates a
                // hard-deleted row when a delete loses) and treat the row as resolved, not a failure.
                if let server = result["server"] as? [String: Any] {
                    try? await syncContainer.sync(
                        item: SyncJSON(dictionary: server), as: Task.self)
                }
            case ("upsert", "applied"), ("delete", "applied"):
                break
            default:
                // Bubble the backend's rejection up as this app's own error. SwiftSync returns the
                // failures verbatim without interpreting them; the engine reads them back to annotate
                // the inbox.
                failures.append(
                    SyncPendingChangesFailure(
                        id: id ?? "",
                        error: DemoUploadRejection(
                            message: (result["message"] as? String) ?? "rejected")))
            }
        }
        return failures
    }

    /// The task's upload payload: its exported scalars plus `reviewer_ids`/`watcher_ids` (which are
    /// `@NotExport`, so `export` omits them) so relationship edits travel with the operation.
    private func taskData(_ task: Task) -> [String: Any] {
        var data = syncContainer.export(task)
        data["reviewer_ids"] = task.reviewers.map(\.id)
        data["watcher_ids"] = task.watchers.map(\.id)
        return data
    }

    /// Apply a payload to the local store as a *local* edit (default author), so it's tracked as a
    /// pending change — unlike `syncContainer.sync(item:)`, which stamps writes as inbound (pulled).
    /// Reuses the `@Syncable`-generated `make`/`apply`, so no field mapping is duplicated here.
    private func applyLocalTask(_ body: SyncJSON, project: Project? = nil) throws {
        let values = body.toSyncPayloadDictionary()
        let payload = SyncPayload(values: values, keyStyle: syncContainer.keyStyle)
        let context = syncContainer.mainContext
        let task: Task
        if let id = payload.value(for: "id", as: String.self), let existing = try self.task(withID: id) {
            _ = try existing.apply(payload)
            task = existing
        } else {
            let created = try Task.make(from: payload)
            context.insert(created)
            if let project { created.project = project }
            task = created
        }
        // reviewers/watchers are @NotExport, so apply()/make() won't set them from the body. Apply the
        // relationships explicitly so an offline people edit shows locally before any server round-trip.
        if let reviewerIDs = values["reviewer_ids"] as? [String] { task.reviewers = try users(for: reviewerIDs) }
        if let watcherIDs = values["watcher_ids"] as? [String] { task.watchers = try users(for: watcherIDs) }
        try context.save()
    }

    /// A task whose only history is a never-pushed local insert (it's in the pending-insert set).
    private func isNeverPushed(_ taskID: String) -> Bool {
        let pending = try? SwiftSync.pendingChanges(for: Task.self, in: syncContainer.mainContext)
        return pending?.inserts.contains(taskID) ?? false
    }

    /// Reflect a push's outcome onto the inbox: stamp `syncFailureReason` on each rejected row and
    /// clear it from any row that no longer fails (it succeeded, or its corrected edit went through).
    /// SwiftSync persists nothing — the failures inbox is entirely this app's concern.
    private func annotateFailures(_ failures: [SyncPendingChangesFailure]) throws {
        let reasonsByID = Dictionary(
            failures.map { ($0.id, $0.error.localizedDescription) },
            uniquingKeysWith: { first, _ in first })
        for task in failedTasks() where reasonsByID[task.id] == nil {
            task.syncFailureReason = nil
        }
        for (id, reason) in reasonsByID {
            if let task = try task(withID: id) { task.syncFailureReason = reason }
        }
        try syncContainer.mainContext.save()
    }

    private func refreshPendingCount() {
        let pending = try? SwiftSync.pendingChanges(for: Task.self, in: syncContainer.mainContext)
        // A rejected row stays pending in the queue (pure-bubble) but reads as *failed*, not *pending* —
        // otherwise the same task is counted twice ("1 pending, 1 failed"). Pending is the queue minus
        // whatever is currently surfaced in the failures inbox. A deleted row is gone from the store, so
        // it can't carry a failure reason — count it as pending regardless.
        let pendingIDs = pending.map { $0.inserts + $0.updates + $0.deletes } ?? []
        let failedIDs = Set(failedTasks().map(\.id))
        pendingChangeCount = pendingIDs.filter { !failedIDs.contains($0) }.count

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
        if isNeverPushed(taskID) {
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

    /// After an inbound pull, refresh the pending count. Freshly-pulled rows aren't mistaken for local
    /// edits because the pull stamps them with the inbound author, which the push side filters out.
    private func markPulled() {
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

    private func syncTaskDetailItem(_ payload: SyncJSON) async throws {
        guard let projectID = payload.string("project_id"), !projectID.isEmpty else {
            throw SyncTaskDetailError.missingProjectID
        }
        guard try project(withID: projectID) != nil else {
            throw SyncTaskDetailError.missingProject(projectID)
        }
        try await syncContainer.sync(item: payload, as: Task.self)
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

    private func syncItemsIfPresent(in payload: SyncJSON, taskID: String) async throws {
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
