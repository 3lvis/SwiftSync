import Foundation
import SwiftData
import Core

public extension SwiftSync {
    static func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        _ = model
        do {
            let entries = try normalize(payload: payload, model: Model.self)
            let existing = try context.fetch(FetchDescriptor<Model>())

            var index: [String: Model] = [:]
            var duplicates: [Model] = []
            for row in existing {
                let key = identityKey(from: row[keyPath: Model.syncIdentity])
                if index[key] != nil {
                    duplicates.append(row)
                    continue
                }
                index[key] = row
            }

            var changed = false
            var seenKeys: Set<String> = []

            if !duplicates.isEmpty {
                for duplicate in duplicates {
                    context.delete(duplicate)
                }
                changed = true
            }

            for entry in entries {
                let payloadModel = SyncPayload(values: entry)
                guard let identity = resolveIdentity(from: payloadModel, model: Model.self) else {
                    // For hardening: rows without valid identity are skipped from matching/diffing.
                    continue
                }
                let key = identityKey(from: identity)
                seenKeys.insert(key)

                if let row = index[key] {
                    if try row.apply(payloadModel) {
                        changed = true
                    }
                    if let relationshipRow = row as? any SyncRelationshipUpdatableModel {
                        if try await relationshipRow.applyRelationships(payloadModel, in: context) {
                            changed = true
                        }
                    }
                    continue
                }

                let created = try Model.make(from: payloadModel)
                context.insert(created)
                if let relationshipRow = created as? any SyncRelationshipUpdatableModel {
                    if try await relationshipRow.applyRelationships(payloadModel, in: context) {
                        changed = true
                    }
                }
                index[key] = created
                changed = true
            }

            for (key, row) in index where !seenKeys.contains(key) {
                context.delete(row)
                changed = true
            }

            if changed {
                try context.save()
            }
            await releaseSyncLease(lease)
        } catch {
            await releaseSyncLease(lease)
            throw error
        }
    }

    static func sync<Model: ParentScopedModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext,
        parent: Model.SyncParent
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        _ = model
        do {
            let entries = try normalize(payload: payload, model: Model.self)
            let existing = try context.fetch(FetchDescriptor<Model>())

            var index: [String: Model] = [:]
            var duplicates: [Model] = []
            for row in existing where row[keyPath: Model.parentRelationship]?.persistentModelID == parent.persistentModelID {
                let key = identityKey(from: row[keyPath: Model.syncIdentity])
                if index[key] != nil {
                    duplicates.append(row)
                    continue
                }
                index[key] = row
            }

            var changed = false
            var seenKeys: Set<String> = []

            if !duplicates.isEmpty {
                for duplicate in duplicates {
                    context.delete(duplicate)
                }
                changed = true
            }

            for entry in entries {
                let payloadModel = SyncPayload(values: entry)
                guard let identity = resolveIdentity(from: payloadModel, model: Model.self) else {
                    continue
                }
                let key = identityKey(from: identity)
                seenKeys.insert(key)

                if let row = index[key] {
                    if row[keyPath: Model.parentRelationship]?.persistentModelID != parent.persistentModelID {
                        row[keyPath: Model.parentRelationship] = parent
                        changed = true
                    }
                    if try row.apply(payloadModel) {
                        changed = true
                    }
                    if let relationshipRow = row as? any SyncRelationshipUpdatableModel {
                        if try await relationshipRow.applyRelationships(payloadModel, in: context) {
                            changed = true
                        }
                    }
                    continue
                }

                let created = try Model.make(from: payloadModel)
                created[keyPath: Model.parentRelationship] = parent
                context.insert(created)
                if let relationshipRow = created as? any SyncRelationshipUpdatableModel {
                    if try await relationshipRow.applyRelationships(payloadModel, in: context) {
                        changed = true
                    }
                }
                index[key] = created
                changed = true
            }

            for (key, row) in index where !seenKeys.contains(key) {
                context.delete(row)
                changed = true
            }

            if changed {
                try context.save()
            }
            await releaseSyncLease(lease)
        } catch {
            await releaseSyncLease(lease)
            throw error
        }
    }

    static func export<Model: ExportModel>(
        as model: Model.Type,
        in context: ModelContext,
        using options: ExportOptions = ExportOptions()
    ) throws -> [[String: Any]] {
        _ = model

        let rows = try context.fetch(FetchDescriptor<Model>())
        let sorted = rows.sorted { lhs, rhs in
            identityKey(from: lhs[keyPath: Model.syncIdentity]) < identityKey(from: rhs[keyPath: Model.syncIdentity])
        }
        return sorted.map { row in
            var state = ExportState()
            return row.exportObject(using: options, state: &state)
        }
    }

    static func export<Model: ExportModel & ParentScopedModel>(
        as model: Model.Type,
        in context: ModelContext,
        parent: Model.SyncParent,
        using options: ExportOptions = ExportOptions()
    ) throws -> [[String: Any]] {
        _ = model

        let rows = try context.fetch(FetchDescriptor<Model>())
            .filter { $0[keyPath: Model.parentRelationship]?.persistentModelID == parent.persistentModelID }
        let sorted = rows.sorted { lhs, rhs in
            identityKey(from: lhs[keyPath: Model.syncIdentity]) < identityKey(from: rhs[keyPath: Model.syncIdentity])
        }
        return sorted.map { row in
            var state = ExportState()
            return row.exportObject(using: options, state: &state)
        }
    }

    private static func normalize<Model: PersistentModel>(payload: [Any], model: Model.Type) throws -> [[String: Any]] {
        try payload.map { raw in
            guard let map = raw as? [String: Any] else {
                throw SyncError.invalidPayload(
                    model: String(describing: model),
                    reason: "Expected array of dictionaries"
                )
            }
            return map
        }
    }

    private static func resolveIdentity<Model: SyncModel>(
        from payload: SyncPayload,
        model: Model.Type
    ) -> Model.SyncID? {
        for key in model.syncIdentityRemoteKeys {
            if let value = payload.value(for: key, as: Model.SyncID.self) {
                return value
            }
        }
        return nil
    }

    private static func identityKey<ID: Hashable>(from identity: ID) -> String {
        String(describing: identity)
    }

    private struct SyncLease {
        let scopeID: ObjectIdentifier
    }

    private actor SyncLeaseRegistry {
        private var activeScopeIDs: Set<ObjectIdentifier> = []
        private var waitersByScopeID: [ObjectIdentifier: [CheckedContinuation<Void, Never>]] = [:]

        func acquire(scopeID: ObjectIdentifier) async -> SyncLease {
            if !activeScopeIDs.contains(scopeID) {
                activeScopeIDs.insert(scopeID)
                return SyncLease(scopeID: scopeID)
            }

            await withCheckedContinuation { continuation in
                var waiters = waitersByScopeID[scopeID] ?? []
                waiters.append(continuation)
                waitersByScopeID[scopeID] = waiters
            }

            return SyncLease(scopeID: scopeID)
        }

        func release(_ lease: SyncLease) {
            var waiters = waitersByScopeID[lease.scopeID] ?? []
            if waiters.isEmpty {
                activeScopeIDs.remove(lease.scopeID)
                return
            }

            let next = waiters.removeFirst()
            if waiters.isEmpty {
                waitersByScopeID.removeValue(forKey: lease.scopeID)
            } else {
                waitersByScopeID[lease.scopeID] = waiters
            }
            next.resume()
        }
    }

    private static let syncLeaseRegistry = SyncLeaseRegistry()

    private static func acquireSyncLease(for context: ModelContext) async -> SyncLease {
        await syncLeaseRegistry.acquire(scopeID: ObjectIdentifier(context.container))
    }

    private static func releaseSyncLease(_ lease: SyncLease) async {
        await syncLeaseRegistry.release(lease)
    }
}
