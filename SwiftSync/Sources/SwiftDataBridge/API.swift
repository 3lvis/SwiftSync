import Foundation
import SwiftData
import Core

public extension SwiftSync {
    static func inferToOneRelationship<Model: PersistentModel, Parent: PersistentModel>(
        for _: Model.Type,
        parent _: Parent.Type
    ) throws -> ReferenceWritableKeyPath<Model, Parent?> {
        try inferSingleParentRelationship(for: Model.self, parent: Parent.self).keyPath
    }

    static func inferToManyRelationship<Model: PersistentModel, Related: PersistentModel>(
        for _: Model.Type,
        related _: Related.Type
    ) throws -> ReferenceWritableKeyPath<Model, [Related]> {
        try inferSingleToManyRelationship(for: Model.self, related: Related.self).keyPath
    }

    static func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as _: Model.Type,
        in context: ModelContext,
        inputKeyStyle: SyncInputKeyStyle = .snakeCase,
        missingRowPolicy: SyncMissingRowPolicy = .delete,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        do {
            try throwIfCancelled()
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
                try throwIfCancelled()
                for duplicate in duplicates {
                    context.delete(duplicate)
                }
                changed = true
            }

            for entry in entries {
                try throwIfCancelled()
                let payloadModel = SyncPayload(values: entry, keyStyle: inputKeyStyle)
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
                    if !relationshipOperations.isDisjoint(with: [.update, .delete]),
                        let relationshipRow = row as? any SyncRelationshipUpdatableModel
                    {
                        try throwIfCancelled()
                        if try await relationshipRow.applyRelationships(
                            payloadModel,
                            in: context,
                            operations: relationshipOperations
                        ) {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                    continue
                }

                let created = try Model.make(from: payloadModel)
                context.insert(created)
                if relationshipOperations.contains(.insert),
                    let relationshipRow = created as? any SyncRelationshipUpdatableModel
                {
                    try throwIfCancelled()
                    if try await relationshipRow.applyRelationships(
                        payloadModel,
                        in: context,
                        operations: relationshipOperations
                    ) {
                        changed = true
                    }
                    try throwIfCancelled()
                }
                index[key] = created
                changed = true
            }

            if missingRowPolicy == .delete {
                try throwIfCancelled()
                for (key, row) in index where !seenKeys.contains(key) {
                    context.delete(row)
                    changed = true
                }
            }

            try throwIfCancelled()
            if changed {
                try context.save()
            }
            await releaseSyncLease(lease)
        } catch {
            if isCancellation(error) {
                context.rollback()
                await releaseSyncLease(lease)
                throw SyncError.cancelled
            }
            await releaseSyncLease(lease)
            throw error
        }
    }

    static func sync<Model: ParentScopedModel>(
        payload: [Any],
        as _: Model.Type,
        in context: ModelContext,
        parent: Model.SyncParent,
        inputKeyStyle: SyncInputKeyStyle = .snakeCase,
        missingRowPolicy: SyncMissingRowPolicy = .delete,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        try await sync(
            payload: payload,
            as: Model.self,
            in: context,
            parent: parent,
            parentRelationship: Model.parentRelationship,
            isGlobal: syncIdentityHasUniqueAttribute(Model.self),
            inputKeyStyle: inputKeyStyle,
            missingRowPolicy: missingRowPolicy,
            relationshipOperations: relationshipOperations
        )
    }

    static func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        payload: [Any],
        as _: Model.Type,
        in context: ModelContext,
        parent: Parent,
        inputKeyStyle: SyncInputKeyStyle = .snakeCase,
        missingRowPolicy: SyncMissingRowPolicy = .delete,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let inferred = try inferToOneRelationship(for: Model.self, parent: Parent.self)
        try await sync(
            payload: payload,
            as: Model.self,
            in: context,
            parent: parent,
            parentRelationship: inferred,
            isGlobal: syncIdentityHasUniqueAttribute(Model.self),
            inputKeyStyle: inputKeyStyle,
            missingRowPolicy: missingRowPolicy,
            relationshipOperations: relationshipOperations
        )
    }

    private static func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        payload: [Any],
        as _: Model.Type,
        in context: ModelContext,
        parent: Parent,
        parentRelationship: ReferenceWritableKeyPath<Model, Parent?>,
        isGlobal: Bool,
        inputKeyStyle: SyncInputKeyStyle,
        missingRowPolicy: SyncMissingRowPolicy,
        relationshipOperations: SyncRelationshipOperations
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        do {
            try throwIfCancelled()
            let entries = try normalize(payload: payload, model: Model.self)
            guard let resolvedParent = try resolveParent(parent, in: context) else {
                throw SyncError.invalidPayload(
                    model: String(describing: Model.self),
                    reason: "Parent must be resolved in the same ModelContext used for sync."
                )
            }
            let existing = try context.fetch(FetchDescriptor<Model>())
            let scopeRows = existing.filter {
                $0[keyPath: parentRelationship]?.persistentModelID == resolvedParent.persistentModelID
            }

            var index: [String: Model] = [:]
            var duplicates: [Model] = []
            if isGlobal {
                for row in existing {
                    let key = identityKey(from: row[keyPath: Model.syncIdentity])
                    if index[key] != nil {
                        duplicates.append(row)
                        continue
                    }
                    index[key] = row
                }
            } else {
                for row in scopeRows {
                    let key = scopedIdentityKey(
                        from: row[keyPath: Model.syncIdentity],
                        parentPersistentID: resolvedParent.persistentModelID
                    )
                    if index[key] != nil {
                        duplicates.append(row)
                        continue
                    }
                    index[key] = row
                }
            }

            var changed = false
            var seenKeys: Set<String> = []

            if !duplicates.isEmpty {
                try throwIfCancelled()
                for duplicate in duplicates {
                    context.delete(duplicate)
                }
                changed = true
            }

            for entry in entries {
                try throwIfCancelled()
                let payloadModel = SyncPayload(values: entry, keyStyle: inputKeyStyle)
                guard let identity = resolveIdentity(from: payloadModel, model: Model.self) else {
                    continue
                }
                let key: String
                if isGlobal {
                    key = identityKey(from: identity)
                } else {
                    key = scopedIdentityKey(
                        from: identity,
                        parentPersistentID: resolvedParent.persistentModelID
                    )
                }
                seenKeys.insert(key)

                if let row = index[key] {
                    if row[keyPath: parentRelationship]?.persistentModelID != resolvedParent.persistentModelID {
                        row[keyPath: parentRelationship] = resolvedParent
                        changed = true
                    }
                    if try row.apply(payloadModel) {
                        changed = true
                    }
                    if !relationshipOperations.isDisjoint(with: [.update, .delete]),
                        let relationshipRow = row as? any SyncRelationshipUpdatableModel
                    {
                        try throwIfCancelled()
                        if try await relationshipRow.applyRelationships(
                            payloadModel,
                            in: context,
                            operations: relationshipOperations
                        ) {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                    continue
                }

                let created = try Model.make(from: payloadModel)
                created[keyPath: parentRelationship] = resolvedParent
                context.insert(created)
                if relationshipOperations.contains(.insert),
                    let relationshipRow = created as? any SyncRelationshipUpdatableModel
                {
                    try throwIfCancelled()
                    if try await relationshipRow.applyRelationships(
                        payloadModel,
                        in: context,
                        operations: relationshipOperations
                    ) {
                        changed = true
                    }
                    try throwIfCancelled()
                }
                index[key] = created
                changed = true
            }

            if missingRowPolicy == .delete {
                try throwIfCancelled()
                for row in scopeRows {
                    let key: String
                    if isGlobal {
                        key = identityKey(from: row[keyPath: Model.syncIdentity])
                    } else {
                        key = scopedIdentityKey(
                            from: row[keyPath: Model.syncIdentity],
                            parentPersistentID: resolvedParent.persistentModelID
                        )
                    }
                    if seenKeys.contains(key) {
                        continue
                    }
                    context.delete(row)
                    changed = true
                }
            }

            try throwIfCancelled()
            if changed {
                try context.save()
            }
            await releaseSyncLease(lease)
        } catch {
            if isCancellation(error) {
                context.rollback()
                await releaseSyncLease(lease)
                throw SyncError.cancelled
            }
            await releaseSyncLease(lease)
            throw error
        }
    }

    static func export<Model: ExportModel>(
        as _: Model.Type,
        in context: ModelContext,
        using options: ExportOptions = ExportOptions()
    ) throws -> [[String: Any]] {
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
        as _: Model.Type,
        in context: ModelContext,
        parent: Model.SyncParent,
        using options: ExportOptions = ExportOptions()
    ) throws -> [[String: Any]] {
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

    private static func resolveIdentity<Model: SyncModelable>(
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

    private static func resolveParent<Parent: PersistentModel>(
        _ parent: Parent,
        in context: ModelContext
    ) throws -> Parent? {
        let parents = try context.fetch(FetchDescriptor<Parent>())
        return parents.first { $0.persistentModelID == parent.persistentModelID }
    }

    private struct ParentRelationshipCandidate<Model: PersistentModel, Parent: PersistentModel> {
        let name: String
        let keyPath: ReferenceWritableKeyPath<Model, Parent?>
    }

    private struct ToManyRelationshipCandidate<Model: PersistentModel, Related: PersistentModel> {
        let name: String
        let keyPath: ReferenceWritableKeyPath<Model, [Related]>
    }

    private static func inferSingleParentRelationship<Model: PersistentModel, Parent: PersistentModel>(
        for _: Model.Type,
        parent _: Parent.Type
    ) throws -> ParentRelationshipCandidate<Model, Parent> {
        var candidates: [ParentRelationshipCandidate<Model, Parent>] = []
        for metadata in Model.schemaMetadata {
            let metadataMirror = Mirror(reflecting: metadata)
            let name = metadataMirror.children.first(where: { $0.label == "name" })?.value as? String ?? "<unknown>"
            guard let keyPathAny = metadataMirror.children.first(where: { $0.label == "keypath" })?.value else {
                continue
            }
            guard let keyPath = keyPathAny as? ReferenceWritableKeyPath<Model, Parent?> else {
                continue
            }
            candidates.append(ParentRelationshipCandidate(name: name, keyPath: keyPath))
        }

        if candidates.isEmpty {
            throw SyncError.invalidPayload(
                model: String(describing: Model.self),
                reason: """
                Could not infer a parent relationship to \(String(describing: Parent.self)). \
                Found 0 candidate to-one relationships. \
                Add explicit ParentScopedModel.parentRelationship for this model.
                """
            )
        }

        if candidates.count > 1 {
            let names = candidates.map(\.name).sorted().joined(separator: ", ")
            throw SyncError.invalidPayload(
                model: String(describing: Model.self),
                reason: """
                Ambiguous parent relationship to \(String(describing: Parent.self)). \
                Found \(candidates.count) candidates: \(names). \
                Add explicit ParentScopedModel.parentRelationship for this model.
                """
            )
        }

        return candidates[0]
    }

    private static func inferSingleToManyRelationship<Model: PersistentModel, Related: PersistentModel>(
        for _: Model.Type,
        related _: Related.Type
    ) throws -> ToManyRelationshipCandidate<Model, Related> {
        var candidates: [ToManyRelationshipCandidate<Model, Related>] = []
        for metadata in Model.schemaMetadata {
            let metadataMirror = Mirror(reflecting: metadata)
            let name = metadataMirror.children.first(where: { $0.label == "name" })?.value as? String ?? "<unknown>"
            guard let keyPathAny = metadataMirror.children.first(where: { $0.label == "keypath" })?.value else {
                continue
            }
            guard let keyPath = keyPathAny as? ReferenceWritableKeyPath<Model, [Related]> else {
                continue
            }
            candidates.append(ToManyRelationshipCandidate(name: name, keyPath: keyPath))
        }

        if candidates.isEmpty {
            throw SyncError.invalidPayload(
                model: String(describing: Model.self),
                reason: """
                Could not infer a to-many relationship to \(String(describing: Related.self)). \
                Found 0 candidate to-many relationships. \
                Pass an explicit query relationship via `via:`.
                """
            )
        }

        if candidates.count > 1 {
            let names = candidates.map(\.name).sorted().joined(separator: ", ")
            throw SyncError.invalidPayload(
                model: String(describing: Model.self),
                reason: """
                Ambiguous to-many relationship to \(String(describing: Related.self)). \
                Found \(candidates.count) candidates: \(names). \
                Pass an explicit query relationship via `via:`.
                """
            )
        }

        return candidates[0]
    }

    private static func syncIdentityHasUniqueAttribute<Model: SyncModelable>(_ model: Model.Type) -> Bool {
        let identityKeyPath = Model.syncIdentity as AnyKeyPath
        for propertyMetadata in Model.schemaMetadata {
            let mirror = Mirror(reflecting: propertyMetadata)
            guard let candidateKeyPath = mirror.children.first(where: { $0.label == "keypath" })?.value as? AnyKeyPath,
                  candidateKeyPath == identityKeyPath else { continue }
            guard let rawMetadata = mirror.children.first(where: { $0.label == "metadata" })?.value else { return false }
            let metadataMirror = Mirror(reflecting: rawMetadata)
            let unwrapped: Any? = metadataMirror.displayStyle == .optional
                ? metadataMirror.children.first?.value
                : rawMetadata
            guard let attribute = unwrapped as? Schema.Attribute else { return false }
            return attribute.options.contains(.unique)
        }
        return false
    }

    private static func identityKey<ID: Hashable>(from identity: ID) -> String {
        String(describing: identity)
    }

    private static func scopedIdentityKey<ID: Hashable>(
        from identity: ID,
        parentPersistentID: PersistentIdentifier
    ) -> String {
        "\(String(reflecting: ID.self))|\(String(describing: parentPersistentID))|\(identityKey(from: identity))"
    }

    private static func throwIfCancelled() throws {
        if Task.isCancelled {
            throw SyncError.cancelled
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let syncError = error as? SyncError, syncError == .cancelled {
            return true
        }
        return false
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
