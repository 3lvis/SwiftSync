import Foundation
import SwiftData
@preconcurrency import SwiftSync

/// The backend's rejection of a pushed row, bubbled up through `SyncPushFailure.error`. This is the
/// app's own error type — SwiftSync carries it verbatim and never interprets it.
public struct DemoUploadRejection: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// The demo's `/sync/upload` transport, registered on the `SyncContainer`. Turns the pending Task ids into
/// the operation list, POSTs it once, and maps the per-row results back to `[SyncPushFailure]`. Every
/// created-or-edited row is an `upsert` keyed by its stable `id` (the server find-by-id → update-else-create,
/// adopting that `id` as the row's `public_id` — no distinct server id comes back); tombstones are a
/// `delete` by the same `id`. A `stale` result means the server won last-writer-wins — adopt its state
/// locally and report no failure for that row (resolved, not rejected).
@MainActor
final class TaskBackend: SyncBackend {
    private unowned let syncContainer: SyncContainer
    private let apiClient: FakeDemoAPIClient

    init(syncContainer: SyncContainer, apiClient: FakeDemoAPIClient) {
        self.syncContainer = syncContainer
        self.apiClient = apiClient
    }

    func push(_ pending: SyncPendingChanges) async throws -> [SyncPushFailure] {
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

        var failures: [SyncPushFailure] = []
        for result in results {
            guard let id = result["id"] as? String else { continue }
            switch result["status"] as? String {
            case "stale":
                // The server won last-writer-wins — adopt its state locally (the inbound sync re-creates a
                // hard-deleted row when a delete loses); the row is resolved, not a failure.
                if let server = result["server"] as? [String: Any] {
                    try? await syncContainer.sync(
                        item: DemoSyncPayload(dictionary: server), as: Task.self)
                }
            case "applied":
                break
            default:
                // Bubble the backend's rejection up as this app's own error; the engine reads it back from
                // the drain result to annotate the failures inbox.
                failures.append(
                    SyncPushFailure(
                        id: id, error: DemoUploadRejection(message: (result["message"] as? String) ?? "rejected")))
            }
        }
        return failures
    }

    private func task(withID id: String) throws -> Task? {
        try syncContainer.mainContext.fetch(
            FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })
        ).first
    }

    /// The task's upload payload: its exported scalars plus `reviewer_ids`/`watcher_ids` (which are
    /// `@NotExport`, so `export` omits them) so relationship edits travel with the operation.
    private func taskData(_ task: Task) -> [String: Any] {
        var data = syncContainer.export(task)
        data["reviewer_ids"] = task.reviewers.map(\.id)
        data["watcher_ids"] = task.watchers.map(\.id)
        return data
    }
}
