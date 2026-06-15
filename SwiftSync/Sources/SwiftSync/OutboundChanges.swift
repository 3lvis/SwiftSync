import Foundation
import SwiftData

/// A model that participates in **outbound** (local → server) sync.
///
/// SwiftSync targets conventional JSON APIs whose backend mints its own ids, so identity is a
/// two-id mapping: `syncLocalID` is the client-generated id that is stable forever, and
/// `syncRemoteID` is the server's id — `nil` until the row has been pushed and acknowledged.
/// `syncUpdatedAt` drives last-writer-wins; `syncIsDeleted` is a soft-delete that survives until
/// the deletion has been pushed (then the row is hard-deleted).
///
/// `package` while the outbound feature is built out slice by slice; promoted to `public` (with
/// README docs) once it is consumer-usable.
package protocol SyncOfflineModel: PersistentModel {
    var syncLocalID: String { get }
    var syncRemoteID: String? { get }
    var syncUpdatedAt: Date { get }
    var syncIsDeleted: Bool { get }
}

/// The local rows that need pushing to the server, partitioned by operation.
package struct SyncPendingChanges<Model: SyncOfflineModel> {
    package let creates: [Model]
    package let updates: [Model]
    package let deletes: [Model]
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
}
