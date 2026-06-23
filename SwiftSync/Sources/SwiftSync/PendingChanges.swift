import Foundation
import SwiftData

// MARK: - Pending changes

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
public struct SyncPendingChangesFailure: Sendable {
    public let id: String
    public let error: any Error & Sendable

    public init(id: String, error: any Error & Sendable) {
        self.id = id
        self.error = error
    }
}

extension SwiftSync {
    /// The transaction author SwiftSync stamps on inbound (pull) writes, so the push side can tell
    /// server-applied changes from genuine local edits and never push pulled rows back. Local edits
    /// use the store's default author; pull writes use this one and are filtered out of `pendingChanges`.
    static let inboundAuthor = "swiftsync.inbound"

    /// The local changes pending a push. A row inserted then edited collapses to a single insert; a row
    /// deleted after editing collapses to a delete (its `id` recovered from the history tombstone — mark
    /// the identity `.preserveValueOnDeletion`).
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

    /// Persistent ids (not row ids — so no `SyncID == String` constraint) of rows with un-pushed local
    /// changes: local-authored history since the stored token.
    private static func locallyDirtyPersistentIDs<Model: SyncUpdatableModel>(
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

    /// A row with un-pushed local changes (its persistent id is in the history dirty-set). `delete-missing`
    /// skips these: a row the user created or edited offline and hasn't pushed yet must survive an
    /// inbound pull that omits it — the server omitting a row it has never seen is not a deletion.
    static func isUnsyncedLocalInsert<Model: SyncUpdatableModel>(
        _ row: Model, dirtyPIDs: Set<PersistentIdentifier>
    ) -> Bool {
        dirtyPIDs.contains(row.persistentModelID)
    }

    /// Apply a server `payload` onto `row`, but skip the overwrite when the row has an un-pushed local
    /// edit (its persistent id is in the dirty-set) — so an inbound pull can't clobber pending local
    /// work. Last-writer-wins, local-wins-while-pending: the local edit is preserved until it's pushed.
    static func applyHonoringLocalEdit<Model: SyncUpdatableModel>(
        _ payload: SyncPayload, to row: Model, dirtyPIDs: Set<PersistentIdentifier>
    ) throws -> Bool {
        if dirtyPIDs.contains(row.persistentModelID) { return false }
        return try row.apply(payload)
    }

    private static func localTransactions(since token: DefaultHistoryToken?, in context: ModelContext) throws
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

    /// `.preserveValueOnDeletion` on the identity is the offline opt-in signal: it lets a deleted row's id
    /// be recovered from its history tombstone (and is a harmless no-op otherwise).
    private static func identityPreservesValueOnDeletion<Model: SyncModelable>(
        _: Model.Type, in context: ModelContext
    ) -> Bool {
        let identityName = Model.syncIdentityPropertyName
        guard !identityName.isEmpty else { return false }
        guard
            let attribute = context.container.schema
                .entities.first(where: { $0.name == String(describing: Model.self) })?
                .attributesByName[identityName]
        else { return false }
        return attribute.options.contains(.preserveValueOnDeletion)
    }

    /// Offline push requires `.preserveValueOnDeletion` on the identity — without it a deleted row's id
    /// can't be recovered and the deletion is silently lost. Fail loudly rather than drop deletes.
    private static func requireOfflineCapable<Model: SyncModelable>(_: Model.Type, in context: ModelContext) throws {
        guard identityPreservesValueOnDeletion(Model.self, in: context) else {
            throw SyncError.schemaValidation(
                reason: """
                    \(String(reflecting: Model.self)) is used with offline push, but its identity \
                    ("\(Model.syncIdentityPropertyName)") is not marked @Attribute(.preserveValueOnDeletion). \
                    Add that option to the identity so deletions can be recovered from store history and pushed.
                    """)
        }
    }
}

// MARK: - Push

extension SwiftSync {
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
        process: (SyncPendingChanges) async throws -> [SyncPendingChangesFailure]
    ) async throws -> [SyncPendingChangesFailure] where Model.SyncID == String {
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

    /// `withPendingChanges` writes `PushHistoryTokenRecord` to advance its bookmark once the upload is
    /// acknowledged. `SyncContainer` registers that model automatically; a caller who builds their own
    /// `ModelContainer` may not. Validate it's in the schema *before* the upload, so an acknowledged
    /// server write is never stranded by a token write that throws afterward.
    private static func requireOfflinePushBookkeeping(in context: ModelContext) throws {
        let name = String(describing: PushHistoryTokenRecord.self)
        guard context.container.schema.entities.contains(where: { $0.name == name }) else {
            throw SyncError.schemaValidation(
                reason: """
                    Offline push needs SwiftSync's bookkeeping model (\(name)) in the context's schema, \
                    but it is missing. Build the container with SyncContainer, which registers it \
                    automatically, so an acknowledged upload is never lost to a failed token write.
                    """)
        }
    }

    private static func lastPushedHistoryToken(for model: any PersistentModel.Type, in context: ModelContext)
        -> DefaultHistoryToken?
    {
        let typeName = String(reflecting: model)
        var descriptor = FetchDescriptor<PushHistoryTokenRecord>(predicate: #Predicate { $0.modelTypeName == typeName })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(DefaultHistoryToken.self, from: record.tokenData)
    }

    private static func setLastPushedHistoryToken(
        _ token: DefaultHistoryToken, for model: any PersistentModel.Type, in context: ModelContext
    )
        throws
    {
        let typeName = String(reflecting: model)
        guard let data = try? JSONEncoder().encode(token) else { return }
        var descriptor = FetchDescriptor<PushHistoryTokenRecord>(predicate: #Predicate { $0.modelTypeName == typeName })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            record.tokenData = data
        } else {
            context.insert(PushHistoryTokenRecord(modelTypeName: typeName, tokenData: data))
        }
        try context.save()
    }

    /// Trim inbound (pull-authored) history through `token`. Only inbound is removed — local-authored
    /// history is the un-pushed-changes signal and must survive.
    private static func trimInboundHistory(through token: DefaultHistoryToken, in context: ModelContext) throws {
        let inbound = inboundAuthor
        try context.deleteHistory(
            HistoryDescriptor<DefaultHistoryTransaction>(
                predicate: #Predicate { $0.token <= token && $0.author == inbound }))
    }
}

/// SwiftSync's "how far have I pushed" bookmark, one row **per model type** (not per data row) — the only
/// durable offline state SwiftSync keeps. The change log itself is SwiftData history; this records the
/// last-pushed `DefaultHistoryToken` so the pull can tell un-pushed local edits from already-pushed ones.
@Model
final class PushHistoryTokenRecord {
    @Attribute(.unique) var modelTypeName: String
    /// A JSON-encoded `DefaultHistoryToken`. Stored as `Data` because the token is a `Codable` value,
    /// not a `@Model`, so SwiftData can't persist it directly.
    var tokenData: Data

    init(modelTypeName: String, tokenData: Data) {
        self.modelTypeName = modelTypeName
        self.tokenData = tokenData
    }
}
