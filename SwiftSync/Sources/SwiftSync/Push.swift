import Foundation
import SwiftData

extension SwiftSync {
    /// The transaction author SwiftSync stamps on inbound (pull) writes, so the push side can tell
    /// server-applied changes from genuine local edits and never push pulled rows back. Local edits
    /// use the store's default author; pull writes use this one and are filtered out of `pendingChanges`.
    public static let inboundAuthor = "swiftsync.inbound"
}

/// The local `localID`s pending a push, partitioned by operation, derived from store history.
public struct SyncPendingChanges: Sendable {
    public let inserts: [String]
    public let updates: [String]
    public let deletes: [String]

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// The `localID`s to push, partitioned by operation. Sendable; the app maps each id to its payload,
/// so SwiftData objects never cross into a network call.
public struct SyncPushBatch: Sendable {
    public let inserts: [String]
    public let updates: [String]
    public let deletes: [String]

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// One pushed item the server rejected. `error` is the consumer's own error, bubbled up verbatim.
public struct SyncPushFailure: Sendable {
    public enum Operation: String, Equatable, Sendable { case insert, update, delete }
    public let localID: String
    public let operation: Operation
    public let error: any Error & Sendable

    public init(localID: String, operation: Operation, error: any Error & Sendable) {
        self.localID = localID
        self.operation = operation
        self.error = error
    }
}

/// What the app's uploader reports back. The client `localID` is the identity the backend adopts, so a
/// push is an idempotent upsert — there are no server-assigned ids to map home — and the response is
/// just the set of acknowledged `localID`s plus any failures.
public struct SyncPushResponse: Sendable {
    public var confirmedLocalIDs: Set<String>
    public var failures: [SyncPushFailure]

    public init(confirmedLocalIDs: Set<String> = [], failures: [SyncPushFailure] = []) {
        self.confirmedLocalIDs = confirmedLocalIDs
        self.failures = failures
    }
}

/// Result of a push pass. SwiftSync advances its own per-type token internally on a fully-acknowledged
/// push, so there is no token for the caller to persist — just the counts and any per-row failures.
public struct SyncPushSummary: Sendable {
    public let insertedCount: Int
    public let updatedCount: Int
    public let deletedCount: Int
    public let failures: [SyncPushFailure]
}

extension SwiftSync {
    /// The local changes pending a push, read straight from SwiftData history since SwiftSync's stored
    /// per-type token: transactions authored by anyone other than the inbound (pull) author. A row
    /// inserted then edited collapses to a single insert; a row deleted after editing collapses to a
    /// delete (its `localID` recovered from the history tombstone — mark the identity
    /// `.preserveValueOnDeletion`).
    public static func pendingChanges<Model: SyncUpdatableModel>(
        for _: Model.Type,
        in context: ModelContext
    ) throws -> SyncPendingChanges where Model.SyncID == String {
        try requireOfflineCapable(Model.self, in: context)
        return try pendingChanges(
            for: Model.self, in: context, since: lastPushedHistoryToken(for: Model.self, in: context))
    }

    static func pendingChanges<Model: SyncUpdatableModel>(
        for _: Model.Type,
        in context: ModelContext,
        since token: DefaultHistoryToken?
    ) throws -> SyncPendingChanges where Model.SyncID == String {
        try pendingChanges(from: localTransactions(since: token, in: context), for: Model.self, in: context)
    }

    /// Separate from the token-driven overload so `push` derives the batch and its pre-upload boundary
    /// token from a single history read (see the boundary capture in `push`).
    static func pendingChanges<Model: SyncUpdatableModel>(
        from transactions: [DefaultHistoryTransaction],
        for _: Model.Type,
        in context: ModelContext
    ) throws -> SyncPendingChanges where Model.SyncID == String {
        // No local changes since the token → nothing to push. Return before the live-row fetch so the
        // common "nothing pending" case is O(history query), not O(table size).
        guard !transactions.isEmpty else {
            return SyncPendingChanges(inserts: [], updates: [], deletes: [])
        }

        // Resolve every changed persistent id to its localID. Live rows come from a fetch; deleted
        // rows are gone from the store, so their (now-invalidated) insert/update changes can't be read
        // — their id comes from the delete tombstone instead (mark the identity `.preserveValueOnDeletion`).
        // Resolving deleted rows lets us recognise an insert-then-delete that never reached the server.
        var idByPID: [PersistentIdentifier: String] = Dictionary(
            try context.fetch(FetchDescriptor<Model>()).map { ($0.persistentModelID, $0[keyPath: Model.syncIdentity]) },
            uniquingKeysWith: { lhs, _ in lhs })
        for transaction in transactions {
            for change in transaction.changes {
                if case .delete(let delete as DefaultHistoryDelete<Model>) = change,
                    let id = delete.tombstone[Model.syncIdentity] as? String
                {
                    idByPID[delete.changedPersistentIdentifier] = id
                }
            }
        }

        var flagsByID: [String: (insert: Bool, update: Bool, delete: Bool)] = [:]
        var orderedIDs: [String] = []
        func flag(_ id: String, _ mutate: (inout (insert: Bool, update: Bool, delete: Bool)) -> Void) {
            if flagsByID[id] == nil {
                flagsByID[id] = (false, false, false)
                orderedIDs.append(id)
            }
            mutate(&flagsByID[id]!)
        }

        for transaction in transactions {
            for change in transaction.changes {
                switch change {
                case .insert(let insert as DefaultHistoryInsert<Model>):
                    if let id = idByPID[insert.changedPersistentIdentifier] { flag(id) { $0.insert = true } }
                case .update(let update as DefaultHistoryUpdate<Model>):
                    if let id = idByPID[update.changedPersistentIdentifier] { flag(id) { $0.update = true } }
                case .delete(let delete as DefaultHistoryDelete<Model>):
                    if let id = delete.tombstone[Model.syncIdentity] as? String { flag(id) { $0.delete = true } }
                default:
                    break
                }
            }
        }

        var inserts: [String] = []
        var updates: [String] = []
        var deletes: [String] = []
        for id in orderedIDs {
            guard let flags = flagsByID[id] else { continue }
            if flags.delete {
                // Inserted *and* deleted while never pushed → the server never saw it, so drop it
                // rather than pushing a delete for a row that doesn't exist server-side.
                if !flags.insert { deletes.append(id) }
            } else if flags.insert {
                inserts.append(id)
            } else if flags.update {
                updates.append(id)
            }
        }
        return SyncPendingChanges(inserts: inserts, updates: updates, deletes: deletes)
    }

    /// Drive one push: read pending changes from history (since the model type's last-pushed token),
    /// hand their ids to the app's `upload` closure (the app owns the network call), then — only when
    /// *every* pending change was acknowledged — advance the last-pushed token to the pre-upload history
    /// boundary and trim the now-redundant inbound history. SwiftSync writes no per-row state on push; an
    /// unacknowledged change simply stays past the token and is re-detected next push.
    @discardableResult
    public static func push<Model: SyncUpdatableModel>(
        for _: Model.Type,
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation,
        upload: (SyncPushBatch) async throws -> SyncPushResponse
    ) async throws -> SyncPushSummary where Model.SyncID == String {
        try requireOfflineCapable(Model.self, in: context)
        try requireOfflinePushBookkeeping(in: context)
        let token = lastPushedHistoryToken(for: Model.self, in: context)
        let transactions = try localTransactions(since: token, in: context)
        let pending = try pendingChanges(from: transactions, for: Model.self, in: context)
        guard !pending.isEmpty else {
            return SyncPushSummary(insertedCount: 0, updatedCount: 0, deletedCount: 0, failures: [])
        }
        // The history head observed *before* the upload. Advancing only to here leaves any write that
        // lands during the upload await past the token, so it's re-detected next push, not swallowed.
        let boundary = transactions.last?.token

        let batch = SyncPushBatch(inserts: pending.inserts, updates: pending.updates, deletes: pending.deletes)
        let response = try await upload(batch)

        let allIDs = Set(pending.inserts + pending.updates + pending.deletes)
        let acknowledgedEverything = response.failures.isEmpty && allIDs.isSubset(of: response.confirmedLocalIDs)

        if acknowledgedEverything, let boundary {
            try setLastPushedHistoryToken(boundary, for: Model.self, in: context)
            try? trimInboundHistory(throughInclusive: boundary, in: context)
        }

        func confirmed(_ ids: [String]) -> Int { ids.filter { response.confirmedLocalIDs.contains($0) }.count }
        return SyncPushSummary(
            insertedCount: confirmed(pending.inserts),
            updatedCount: confirmed(pending.updates),
            deletedCount: confirmed(pending.deletes),
            failures: response.failures)
    }

    /// Dirty persistent ids for the pull, but only for models that opted into offline round-trip by
    /// marking their identity `.preserveValueOnDeletion`. A plain (non-offline) model gets an empty
    /// set, so its pull keeps "server is authoritative, always apply" semantics — the behavior the core
    /// diffing tests rely on.
    static func offlineDirtyPersistentIDs<Model: SyncUpdatableModel>(
        for _: Model.Type, in context: ModelContext
    ) -> Set<PersistentIdentifier> {
        guard identityPreservesValueOnDeletion(Model.self, in: context) else { return [] }
        return (try? locallyDirtyPersistentIDs(for: Model.self, in: context)) ?? []
    }

    /// The persistent identifiers of rows with **un-pushed local changes** for `Model` — local-authored
    /// history since the stored token. The pull uses this to preserve never-pushed local inserts from
    /// delete-missing and to keep a newer local edit from being clobbered (last-writer-wins). Reads
    /// persistent ids (not localIDs), so it needs no `SyncID == String` constraint.
    static func locallyDirtyPersistentIDs<Model: SyncUpdatableModel>(
        for _: Model.Type, in context: ModelContext
    ) throws -> Set<PersistentIdentifier> {
        let transactions = try localTransactions(
            since: lastPushedHistoryToken(for: Model.self, in: context), in: context)
        var ids: Set<PersistentIdentifier> = []
        for transaction in transactions {
            for change in transaction.changes {
                switch change {
                case .insert(let insert as DefaultHistoryInsert<Model>): ids.insert(insert.changedPersistentIdentifier)
                case .update(let update as DefaultHistoryUpdate<Model>): ids.insert(update.changedPersistentIdentifier)
                default: break
                }
            }
        }
        return ids
    }

    /// Trim inbound (pull-authored) history up to and including `token`. Only inbound transactions are
    /// removed — local-authored history is the un-pushed-changes signal and a different model type may
    /// still need its own un-pushed local changes, so those are never trimmed here.
    static func trimInboundHistory(throughInclusive token: DefaultHistoryToken, in context: ModelContext) throws {
        let inbound = inboundAuthor
        try context.deleteHistory(
            HistoryDescriptor<DefaultHistoryTransaction>(
                predicate: #Predicate { $0.token <= token && $0.author == inbound }))
    }

    /// History transactions since `token` that were *not* authored by the inbound (pull) writer.
    static func localTransactions(since token: DefaultHistoryToken?, in context: ModelContext) throws
        -> [DefaultHistoryTransaction]
    {
        // A local write leaves `author` nil; in predicate/SQL semantics `nil != "inbound"` is NULL
        // (not true), which would wrongly exclude local changes. Match "nil OR not inbound" explicitly.
        let inbound = inboundAuthor
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token {
            descriptor.predicate = #Predicate {
                $0.token > token && ($0.author == nil || $0.author != inbound)
            }
        } else {
            descriptor.predicate = #Predicate { $0.author == nil || $0.author != inbound }
        }
        return try context.fetchHistory(descriptor)
    }
}
