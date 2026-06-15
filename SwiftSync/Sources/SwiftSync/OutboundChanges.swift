import Foundation
import SwiftData

/// A model that participates in **outbound** (local → server) sync.
///
/// SwiftSync targets conventional JSON APIs whose backend mints its own ids, so identity is a
/// two-id mapping: `syncLocalID` is the client-generated id that is stable forever, and
/// `syncRemoteID` is the server's id — `nil` until the row has been pushed and acknowledged (the
/// push driver assigns it). `syncUpdatedAt` drives last-writer-wins; `syncIsDeleted` is a
/// soft-delete that survives until the deletion is pushed (then the row is hard-deleted).
///
/// `package` while the outbound feature is built out; promoted to `public` (with README docs) once
/// it is consumer-usable.
package protocol SyncOfflineModel: PersistentModel {
    var syncLocalID: String { get }
    var syncRemoteID: String? { get set }
    var syncUpdatedAt: Date { get }
    var syncIsDeleted: Bool { get }
}

/// The local rows that need pushing to the server, partitioned by operation.
package struct SyncPendingChanges<Model: SyncOfflineModel> {
    package let creates: [Model]
    package let updates: [Model]
    package let deletes: [Model]

    package var isEmpty: Bool { creates.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// A single outbound item the server rejected. SwiftSync surfaces these so the app can let the user
/// act on them (discard / edit / retry) rather than silently retrying forever.
package struct SyncOutboundFailure: Equatable, Sendable {
    package enum Operation: String, Equatable, Sendable { case create, update, delete }
    package let localID: String
    package let operation: Operation
    package let message: String

    package init(localID: String, operation: Operation, message: String) {
        self.localID = localID
        self.operation = operation
        self.message = message
    }
}

/// The `syncLocalID`s to push, partitioned by operation. This — not the live models — is what the
/// async uploader receives, so SwiftData objects never cross into a network call (the
/// "never pass a model across contexts" rule). It's `Sendable`; the app maps each id to its payload.
package struct SyncOutboundBatch: Sendable {
    package let creates: [String]
    package let updates: [String]
    package let deletes: [String]

    package var isEmpty: Bool { creates.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// What the app's uploader reports back after talking to the server: the server-assigned ids for
/// created rows, which updates/deletes were accepted, and any per-item failures.
package struct SyncUploadOutcome: Sendable {
    /// create's `syncLocalID` → server-assigned `syncRemoteID`.
    package var assignedRemoteIDs: [String: String]
    package var confirmedUpdateLocalIDs: Set<String>
    package var confirmedDeleteLocalIDs: Set<String>
    package var failures: [SyncOutboundFailure]

    package init(
        assignedRemoteIDs: [String: String] = [:],
        confirmedUpdateLocalIDs: Set<String> = [],
        confirmedDeleteLocalIDs: Set<String> = [],
        failures: [SyncOutboundFailure] = []
    ) {
        self.assignedRemoteIDs = assignedRemoteIDs
        self.confirmedUpdateLocalIDs = confirmedUpdateLocalIDs
        self.confirmedDeleteLocalIDs = confirmedDeleteLocalIDs
        self.failures = failures
    }
}

/// Result of a push pass. Advance the caller's stored "last synced" cursor to `cursor` on success.
package struct SyncPushSummary {
    package let createdCount: Int
    package let updatedCount: Int
    package let deletedCount: Int
    package let failures: [SyncOutboundFailure]
    package let cursor: Date
}

extension SwiftSync {
    /// Partition a store's rows into the outbound work to push, relative to `changedSince` (the last
    /// successful sync). Detection is a query over the store — no save-interception:
    ///
    /// - **create**: never synced (`syncRemoteID == nil`) and not deleted.
    /// - **update**: synced (`syncRemoteID != nil`), not deleted, edited since the last sync.
    /// - **delete**: soft-deleted *and* known to the server (a row created-then-deleted locally
    ///   never reached the server, so it's dropped, not pushed).
    package static func pendingOutboundChanges<Model: SyncOfflineModel>(
        for _: Model.Type,
        in context: ModelContext,
        changedSince: Date
    ) throws -> SyncPendingChanges<Model> {
        let rows = try context.fetch(FetchDescriptor<Model>())

        var creates: [Model] = []
        var updates: [Model] = []
        var deletes: [Model] = []
        for row in rows {
            let synced = row.syncRemoteID != nil
            if row.syncIsDeleted {
                if synced { deletes.append(row) }  // never-synced + deleted → drop, don't push
            } else if !synced {
                creates.append(row)
            } else if row.syncUpdatedAt > changedSince {
                updates.append(row)
            }
        }
        return SyncPendingChanges(creates: creates, updates: updates, deletes: deletes)
    }

    /// Drive one outbound push: detect pending changes, hand them to the app's `upload` closure
    /// (the app owns the network call), then apply the server's outcome locally — stamp
    /// server-assigned `syncRemoteID`s onto created rows, hard-delete confirmed deletes — and report
    /// failures for the app to surface. Returns a summary; advance your "last synced" cursor to
    /// `summary.cursor` on success.
    @discardableResult
    package static func pushPendingChanges<Model: SyncOfflineModel>(
        for _: Model.Type,
        in context: ModelContext,
        changedSince: Date,
        now: Date = Date(),
        isolation: isolated (any Actor)? = #isolation,
        upload: (SyncOutboundBatch) async throws -> SyncUploadOutcome
    ) async throws -> SyncPushSummary {
        let pending = try pendingOutboundChanges(
            for: Model.self, in: context, changedSince: changedSince)
        guard !pending.isEmpty else {
            return SyncPushSummary(
                createdCount: 0, updatedCount: 0, deletedCount: 0, failures: [], cursor: now)
        }

        let batch = SyncOutboundBatch(
            creates: pending.creates.map(\.syncLocalID),
            updates: pending.updates.map(\.syncLocalID),
            deletes: pending.deletes.map(\.syncLocalID))
        let outcome = try await upload(batch)

        var createdCount = 0
        for create in pending.creates {
            if let remoteID = outcome.assignedRemoteIDs[create.syncLocalID] {
                create.syncRemoteID = remoteID
                createdCount += 1
            }
        }

        var deletedCount = 0
        for delete in pending.deletes where outcome.confirmedDeleteLocalIDs.contains(delete.syncLocalID) {
            context.delete(delete)
            deletedCount += 1
        }

        try context.save()

        return SyncPushSummary(
            createdCount: createdCount,
            updatedCount: outcome.confirmedUpdateLocalIDs.count,
            deletedCount: deletedCount,
            failures: outcome.failures,
            cursor: now)
    }
}
