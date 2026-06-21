import Foundation
import SwiftData

extension SwiftSync {
    /// The transaction author SwiftSync stamps on inbound (pull) writes, so the push side can tell
    /// server-applied changes from genuine local edits and never push pulled rows back. Local edits
    /// use the store's default author; pull writes use this one and are filtered out of `pendingChanges`.
    static let inboundAuthor = "swiftsync.inbound"
}

/// Each array holds row `id`s (strings), not objects, so SwiftData objects never cross into your network
/// call: `withPendingChanges` hands you the ids and you map each to your own request payload.
public struct SyncPendingChanges: Sendable {
    public let inserts: [String]
    public let updates: [String]
    public let deletes: [String]

    public var isEmpty: Bool { inserts.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// One pushed row the server rejected: the row `id` (kept pending) and the consumer's own `error`,
/// bubbled up verbatim. Return only these from your `process` closure — the operation that failed is the
/// library's to track, not yours.
public struct SyncPushFailure: Sendable {
    public let id: String
    public let error: any Error & Sendable

    public init(id: String, error: any Error & Sendable) {
        self.id = id
        self.error = error
    }
}

extension SwiftSync {
    /// The local changes pending a push, read straight from SwiftData history since SwiftSync's stored
    /// per-type token: transactions authored by anyone other than the inbound (pull) author. A row
    /// inserted then edited collapses to a single insert; a row deleted after editing collapses to a
    /// delete (its `id` recovered from the history tombstone — mark the identity
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

    /// Separate from the token-driven overload so `withPendingChanges` derives the batch and its
    /// `uploadedThrough` token from a single history read (see the capture in `withPendingChanges`).
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

        // Resolve every changed persistent id to its id. Live rows come from a fetch; deleted
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

    /// Hands your `process` closure the rows changed since the last-pushed token; you own the network call
    /// and return the rejections. Everything you *don't* return is treated as confirmed — the client id is
    /// the identity the server adopts, so it's an idempotent upsert with nothing to acknowledge. Only a
    /// fully clean pass (no failures) advances the token and trims the now-redundant inbound history;
    /// SwiftSync keeps no per-row state, so a failed — or any un-pushed — change stays past the token and
    /// is re-detected next call.
    @discardableResult
    public static func withPendingChanges<Model: SyncUpdatableModel>(
        for _: Model.Type,
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation,
        process: (SyncPendingChanges) async throws -> [SyncPushFailure]
    ) async throws -> [SyncPushFailure] where Model.SyncID == String {
        try requireOfflineCapable(Model.self, in: context)
        try requireOfflinePushBookkeeping(in: context)
        let token = lastPushedHistoryToken(for: Model.self, in: context)
        let transactions = try localTransactions(since: token, in: context)
        let pending = try pendingChanges(from: transactions, for: Model.self, in: context)
        guard !pending.isEmpty else { return [] }
        // The newest history token in this batch, captured *before* the upload. On success we advance the
        // token only to here — never to the live head — so any local write that lands during the upload
        // await stays past the token and is re-detected next push, instead of being silently skipped.
        let uploadedThrough = transactions.last?.token

        let failures = try await process(pending)
        if failures.isEmpty, let uploadedThrough {
            try setLastPushedHistoryToken(uploadedThrough, for: Model.self, in: context)
            try? trimInboundHistory(through: uploadedThrough, in: context)
        }
        return failures
    }

    /// Dirty persistent ids for the pull, but only for models that opted into offline round-trip by
    /// marking their identity `.preserveValueOnDeletion`. A plain (non-offline) model gets an empty
    /// set, so its pull keeps "server is authoritative, always apply" semantics — the behavior the core
    /// diffing tests rely on. Capture it before applying the payload, so the pull honors pending local
    /// edits and never prunes a never-pushed local insert.
    static func offlineDirtyPersistentIDs<Model: SyncUpdatableModel>(
        for _: Model.Type, in context: ModelContext
    ) -> Set<PersistentIdentifier> {
        guard identityPreservesValueOnDeletion(Model.self, in: context) else { return [] }
        return (try? locallyDirtyPersistentIDs(for: Model.self, in: context)) ?? []
    }

    /// The persistent identifiers of rows with **un-pushed local changes** for `Model` — local-authored
    /// history since the stored token. The pull uses this to preserve never-pushed local inserts from
    /// delete-missing and to keep a newer local edit from being clobbered (last-writer-wins). Reads
    /// persistent ids (not row ids), so it needs no `SyncID == String` constraint.
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
    static func trimInboundHistory(through token: DefaultHistoryToken, in context: ModelContext) throws {
        let inbound = inboundAuthor
        try context.deleteHistory(
            HistoryDescriptor<DefaultHistoryTransaction>(
                predicate: #Predicate { $0.token <= token && $0.author == inbound }))
    }

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
