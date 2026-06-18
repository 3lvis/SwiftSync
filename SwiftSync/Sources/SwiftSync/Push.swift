import Foundation
import SwiftData

/// A model that participates in **push** (local → server) sync — the counterpart to the inbound
/// `SwiftSync.sync` (pull).
///
/// SwiftSync targets conventional JSON APIs whose backend mints its own ids, so identity is a
/// two-id mapping: `syncLocalID` is the client-generated id that is stable forever, and
/// `syncRemoteID` is the server's id — `nil` until the row has been pushed and acknowledged (the
/// push driver assigns it). `syncUpdatedAt` drives last-writer-wins; `syncIsDeleted` is a
/// soft-delete that survives until the deletion is pushed (then the row is hard-deleted).
public protocol SyncOfflineModel: PersistentModel {
    var syncLocalID: String { get }
    var syncRemoteID: String? { get set }
    var syncUpdatedAt: Date { get }
    var syncIsDeleted: Bool { get }
}

/// The local rows pending a push, partitioned by operation (live models, for applying results).
public struct SyncPendingChanges<Model: SyncOfflineModel> {
    public let inserts: [Model]
    public let updates: [Model]
    public let deletes: [Model]

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// The `syncLocalID`s to push, partitioned by operation. This — not the live models — is what the
/// async uploader receives, so SwiftData objects never cross into a network call (the
/// "never pass a model across contexts" rule). It's `Sendable`; the app maps each id to its payload.
public struct SyncPushBatch: Sendable {
    public let inserts: [String]
    public let updates: [String]
    public let deletes: [String]

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// One pushed item the server rejected. SwiftSync surfaces these so the app can let the user act on
/// them (discard / edit / retry) rather than silently retrying forever.
public struct SyncPushFailure: Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable { case insert, update, delete }
    public let localID: String
    public let operation: Operation
    public let message: String

    public init(localID: String, operation: Operation, message: String) {
        self.localID = localID
        self.operation = operation
        self.message = message
    }
}

/// What the app's uploader reports back after talking to the server: the server-assigned ids for
/// inserted rows, which updates/deletes were accepted, and any per-item failures.
public struct SyncPushResponse: Sendable {
    /// insert's `syncLocalID` → server-assigned `syncRemoteID`.
    public var assignedRemoteIDs: [String: String]
    public var confirmedUpdateLocalIDs: Set<String>
    public var confirmedDeleteLocalIDs: Set<String>
    public var failures: [SyncPushFailure]

    public init(
        assignedRemoteIDs: [String: String] = [:],
        confirmedUpdateLocalIDs: Set<String> = [],
        confirmedDeleteLocalIDs: Set<String> = [],
        failures: [SyncPushFailure] = []
    ) {
        self.assignedRemoteIDs = assignedRemoteIDs
        self.confirmedUpdateLocalIDs = confirmedUpdateLocalIDs
        self.confirmedDeleteLocalIDs = confirmedDeleteLocalIDs
        self.failures = failures
    }
}

/// Result of a push pass. Advance the caller's stored "last synced" cursor to `cursor` on success.
public struct SyncPushSummary {
    public let insertedCount: Int
    public let updatedCount: Int
    public let deletedCount: Int
    public let failures: [SyncPushFailure]
    public let cursor: Date
}

extension SwiftSync {
    /// Partition a store's rows into the changes pending a push, relative to `changedSince` (the last
    /// successful sync). Detection is a query over the store — no save-interception:
    ///
    /// - **insert**: never synced (`syncRemoteID == nil`) and not deleted.
    /// - **update**: synced (`syncRemoteID != nil`), not deleted, edited since the last sync.
    /// - **delete**: soft-deleted *and* known to the server (a row inserted-then-deleted locally
    ///   never reached the server, so it's dropped, not pushed).
    public static func pendingChanges<Model: SyncOfflineModel>(
        for _: Model.Type,
        in context: ModelContext,
        changedSince: Date
    ) throws -> SyncPendingChanges<Model> {
        let rows = try context.fetch(FetchDescriptor<Model>())

        var inserts: [Model] = []
        var updates: [Model] = []
        var deletes: [Model] = []
        for row in rows {
            let synced = row.syncRemoteID != nil
            if row.syncIsDeleted {
                if synced { deletes.append(row) }  // never-synced + deleted → drop, don't push
            } else if !synced {
                inserts.append(row)
            } else if row.syncUpdatedAt > changedSince {
                updates.append(row)
            }
        }
        return SyncPendingChanges(inserts: inserts, updates: updates, deletes: deletes)
    }

    /// Drive one push: detect pending changes, hand their ids (a Sendable `SyncPushBatch`) to the
    /// app's `upload` closure (the app owns the network call), then apply the server's response
    /// locally — stamp server-assigned `syncRemoteID`s onto inserted rows, hard-delete confirmed
    /// deletes — and report failures for the app to surface. Always advance your "last synced"
    /// cursor to `summary.cursor`: it only moves forward when *every* pending update was
    /// acknowledged, so an unacknowledged update is safely re-detected on the next push.
    @discardableResult
    public static func push<Model: SyncOfflineModel>(
        for _: Model.Type,
        in context: ModelContext,
        changedSince: Date,
        now: Date = Date(),
        isolation: isolated (any Actor)? = #isolation,
        upload: (SyncPushBatch) async throws -> SyncPushResponse
    ) async throws -> SyncPushSummary {
        let pending = try pendingChanges(for: Model.self, in: context, changedSince: changedSince)
        guard !pending.isEmpty else {
            return SyncPushSummary(
                insertedCount: 0, updatedCount: 0, deletedCount: 0, failures: [], cursor: now)
        }

        let batch = SyncPushBatch(
            inserts: pending.inserts.map(\.syncLocalID),
            updates: pending.updates.map(\.syncLocalID),
            deletes: pending.deletes.map(\.syncLocalID))
        let response = try await upload(batch)

        var insertedCount = 0
        for insert in pending.inserts {
            if let remoteID = response.assignedRemoteIDs[insert.syncLocalID] {
                insert.syncRemoteID = remoteID
                insertedCount += 1
            }
        }

        var deletedCount = 0
        for delete in pending.deletes where response.confirmedDeleteLocalIDs.contains(delete.syncLocalID) {
            context.delete(delete)
            deletedCount += 1
        }

        try context.save()

        // Updates are cursor-gated, so only count/advance for updates actually in this batch — and
        // only advance the cursor when *every* pending update was acknowledged. An unacknowledged
        // update (a failure, or one the server silently ignored) would otherwise fall out of future
        // detection and be lost. Inserts and deletes self-gate (remoteID stays nil / isDeleted stays
        // true until applied), so they don't constrain the cursor.
        let pendingUpdateIDs = Set(pending.updates.map(\.syncLocalID))
        let confirmedUpdateIDs = response.confirmedUpdateLocalIDs.intersection(pendingUpdateIDs)
        let allUpdatesAcknowledged = confirmedUpdateIDs.count == pendingUpdateIDs.count

        return SyncPushSummary(
            insertedCount: insertedCount,
            updatedCount: confirmedUpdateIDs.count,
            deletedCount: deletedCount,
            failures: response.failures,
            cursor: allUpdatesAcknowledged ? now : changedSince)
    }
}
