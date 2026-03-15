import Foundation
import SwiftData

extension SwiftSync {
    static func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as _: Model.Type,
        in context: ModelContext,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        do {
            try throwIfCancelled()
            try await withRelationshipLookupCache {
                let entries = try syncProfile("normalize-payload") {
                    try normalize(payload: payload, model: Model.self)
                }
                let existing = try syncProfile("fetch-existing") {
                    try context.fetch(FetchDescriptor<Model>())
                }

                var index: [String: Model] = [:]
                var duplicates: [Model] = []
                syncProfile("build-index") {
                    for row in existing {
                        let key = identityKey(from: row[keyPath: Model.syncIdentity])
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
                    syncProfile("delete-duplicates") {
                        for duplicate in duplicates {
                            context.delete(duplicate)
                        }
                    }
                    changed = true
                }

                for entry in entries {
                    try throwIfCancelled()
                    let payloadModel = SyncPayload(values: entry, keyStyle: keyStyle)
                    guard let identity = resolveIdentity(from: payloadModel, model: Model.self) else {
                        continue
                    }
                    let key = identityKey(from: identity)
                    seenKeys.insert(key)

                    if let row = index[key] {
                        let didApplyFields = try syncProfile("apply-fields") {
                            try row.apply(payloadModel)
                        }
                        if didApplyFields {
                            changed = true
                        }
                        if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                            try throwIfCancelled()
                            let didApplyRelationships = try await syncProfile("apply-relationships") {
                                try await row.applyRelationships(
                                    payloadModel,
                                    in: context,
                                    operations: relationshipOperations
                                )
                            }
                            if didApplyRelationships {
                                changed = true
                            }
                            try throwIfCancelled()
                        }
                        continue
                    }

                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    context.insert(created)
                    if relationshipOperations.contains(.insert) {
                        try throwIfCancelled()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await created.applyRelationships(
                                payloadModel,
                                in: context,
                                operations: relationshipOperations
                            )
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                    index[key] = created
                    changed = true
                }

                try throwIfCancelled()
                syncProfile("delete-missing") {
                    for (key, row) in index where !seenKeys.contains(key) {
                        context.delete(row)
                        changed = true
                    }
                }
                
                try throwIfCancelled()
                if changed {
                    try syncProfile("save-context") {
                        try context.save()
                    }
                }
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

    static func sync<Model: SyncUpdatableModel>(
        item: [String: Any],
        as _: Model.Type,
        in context: ModelContext,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        do {
            try throwIfCancelled()
            try await withRelationshipLookupCache {
                let payloadModel = syncProfile("normalize-payload") {
                    SyncPayload(values: item, keyStyle: keyStyle)
                }
                guard let identity = resolveIdentity(from: payloadModel, model: Model.self) else {
                    return
                }
                let key = identityKey(from: identity)
                var changed = false
                let matchingRow: Model?
                if syncIdentityHasUniqueAttribute(Model.self),
                   Model.syncIdentityPredicate(matching: identity) != nil {
                    matchingRow = try syncProfile("fetch-existing-by-identity") {
                        try fetchUniqueRow(matching: identity, as: Model.self, in: context)
                    }
                } else {
                    let existing = try syncProfile("fetch-existing") {
                        try context.fetch(FetchDescriptor<Model>())
                    }
                    matchingRow = syncProfile("find-existing") {
                        existing.first(where: { identityKey(from: $0[keyPath: Model.syncIdentity]) == key })
                    }
                }
                if let row = matchingRow {
                    let didApplyFields = try syncProfile("apply-fields") {
                        try row.apply(payloadModel)
                    }
                    if didApplyFields { changed = true }
                    if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                        try throwIfCancelled()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await row.applyRelationships(payloadModel, in: context, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                } else {
                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    context.insert(created)
                    if relationshipOperations.contains(.insert) {
                        try throwIfCancelled()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await created.applyRelationships(payloadModel, in: context, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                    changed = true
                }

                try throwIfCancelled()
                if changed {
                    try syncProfile("save-context") { try context.save() }
                }
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

    static func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        item: [String: Any],
        as _: Model.Type,
        in context: ModelContext,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        do {
            try throwIfCancelled()
            try await withRelationshipLookupCache {
                let payloadModel = syncProfile("normalize-payload") {
                    SyncPayload(values: item, keyStyle: keyStyle)
                }
                guard let identity = resolveIdentity(from: payloadModel, model: Model.self) else {
                    return
                }
                let key = identityKey(from: identity)
                let resolvedParent = try syncProfile("resolve-parent", operation: {
                    try resolveParent(parent, in: context)
                })
                guard let resolvedParent else {
                    throw SyncError.invalidPayload(
                        model: String(describing: Model.self),
                        reason: "Parent must be resolved in the same ModelContext used for sync."
                    )
                }
                var changed = false
                let matchingRow: Model?
                if syncIdentityHasUniqueAttribute(Model.self),
                   Model.syncIdentityPredicate(matching: identity) != nil {
                    matchingRow = try syncProfile("fetch-existing-by-identity") {
                        try fetchUniqueRow(matching: identity, as: Model.self, in: context)
                    }
                } else {
                    let existing = try syncProfile("fetch-existing") {
                        try context.fetch(FetchDescriptor<Model>())
                    }
                    let scopeRows = syncProfile("filter-scope") {
                        existing.filter {
                            $0[keyPath: relationship]?.persistentModelID == resolvedParent.persistentModelID
                        }
                    }
                    matchingRow = syncProfile("find-existing") {
                        scopeRows.first(where: { identityKey(from: $0[keyPath: Model.syncIdentity]) == key })
                    }
                }
                if let row = matchingRow {
                    syncProfile("apply-parent") {
                        if row[keyPath: relationship]?.persistentModelID != resolvedParent.persistentModelID {
                            row[keyPath: relationship] = resolvedParent
                            changed = true
                        }
                    }
                    let didApplyFields = try syncProfile("apply-fields") {
                        try row.apply(payloadModel)
                    }
                    if didApplyFields { changed = true }
                    if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                        try throwIfCancelled()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await row.applyRelationships(payloadModel, in: context, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                } else {
                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    syncProfile("apply-parent") {
                        created[keyPath: relationship] = resolvedParent
                    }
                    context.insert(created)
                    if relationshipOperations.contains(.insert) {
                        try throwIfCancelled()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await created.applyRelationships(payloadModel, in: context, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                    changed = true
                }

                try throwIfCancelled()
                if changed { try syncProfile("save-context") { try context.save() } }
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

    static func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        payload: [Any],
        as _: Model.Type,
        in context: ModelContext,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        try await sync(
            payload: payload,
            as: Model.self,
            in: context,
            parent: parent,
            parentRelationship: relationship,
            isGlobal: syncIdentityHasUniqueAttribute(Model.self),
            keyStyle: keyStyle,
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
        keyStyle: KeyStyle,
        relationshipOperations: SyncRelationshipOperations
    ) async throws {
        let lease = await acquireSyncLease(for: context)
        do {
            try throwIfCancelled()
            try await withRelationshipLookupCache {
                let entries = try syncProfile("normalize-payload") {
                    try normalize(payload: payload, model: Model.self)
                }
                let resolvedParent = try syncProfile("resolve-parent", operation: {
                    try resolveParent(parent, in: context)
                })
                guard let resolvedParent else {
                    throw SyncError.invalidPayload(
                        model: String(describing: Model.self),
                        reason: "Parent must be resolved in the same ModelContext used for sync."
                    )
                }
                let parentPredicate = Model.syncParentPredicate(
                    parentPersistentID: resolvedParent.persistentModelID,
                    relationship: parentRelationship
                )
                let scopeRows: [Model]
                if let parentPredicate {
                    scopeRows = try syncProfile("fetch-existing-by-parent") {
                        try context.fetch(FetchDescriptor<Model>(predicate: parentPredicate))
                    }
                } else {
                    let fetchedExisting = try syncProfile("fetch-existing") {
                        try context.fetch(FetchDescriptor<Model>())
                    }
                    scopeRows = syncProfile("filter-scope") {
                        fetchedExisting.filter {
                            $0[keyPath: parentRelationship]?.persistentModelID == resolvedParent.persistentModelID
                        }
                    }
                }

                var index: [String: Model] = [:]
                var duplicates: [Model] = []
                syncProfile("build-index") {
                    if isGlobal {
                        for row in scopeRows {
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
                }

                var changed = false
                var seenKeys: Set<String> = []

                if !duplicates.isEmpty {
                    try throwIfCancelled()
                    syncProfile("delete-duplicates") {
                        for duplicate in duplicates {
                            context.delete(duplicate)
                        }
                    }
                    changed = true
                }

                for entry in entries {
                    try throwIfCancelled()
                    let payloadModel = SyncPayload(values: entry, keyStyle: keyStyle)
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
                        syncProfile("apply-parent") {
                            if row[keyPath: parentRelationship]?.persistentModelID != resolvedParent.persistentModelID {
                                row[keyPath: parentRelationship] = resolvedParent
                                changed = true
                            }
                        }
                        let didApplyFields = try syncProfile("apply-fields") {
                            try row.apply(payloadModel)
                        }
                        if didApplyFields {
                            changed = true
                        }
                        if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                            try throwIfCancelled()
                            let didApplyRelationships = try await syncProfile("apply-relationships") {
                                try await row.applyRelationships(
                                    payloadModel,
                                    in: context,
                                    operations: relationshipOperations
                                )
                            }
                            if didApplyRelationships {
                                changed = true
                            }
                            try throwIfCancelled()
                        }
                        continue
                    }

                    if isGlobal {
                        let movedRow = try syncProfile("fetch-existing-by-identity", operation: {
                            try fetchUniqueRow(matching: identity, as: Model.self, in: context)
                        })
                        if let movedRow {
                            syncProfile("apply-parent") {
                                if movedRow[keyPath: parentRelationship]?.persistentModelID != resolvedParent.persistentModelID {
                                    movedRow[keyPath: parentRelationship] = resolvedParent
                                    changed = true
                                }
                            }
                            let didApplyFields = try syncProfile("apply-fields") {
                                try movedRow.apply(payloadModel)
                            }
                            if didApplyFields {
                                changed = true
                            }
                            if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                                try throwIfCancelled()
                                let didApplyRelationships = try await syncProfile("apply-relationships") {
                                    try await movedRow.applyRelationships(
                                        payloadModel,
                                        in: context,
                                        operations: relationshipOperations
                                    )
                                }
                                if didApplyRelationships {
                                    changed = true
                                }
                                try throwIfCancelled()
                            }
                            index[key] = movedRow
                            continue
                        }
                    }

                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    syncProfile("apply-parent") {
                        created[keyPath: parentRelationship] = resolvedParent
                    }
                    context.insert(created)
                    if relationshipOperations.contains(.insert) {
                        try throwIfCancelled()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await created.applyRelationships(
                                payloadModel,
                                in: context,
                                operations: relationshipOperations
                            )
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try throwIfCancelled()
                    }
                    index[key] = created
                    changed = true
                }

                try throwIfCancelled()
                syncProfile("delete-missing") {
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
                    try syncProfile("save-context") {
                        try context.save()
                    }
                }
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

    private static func resolveParent<Parent: PersistentModel>(
        _ parent: Parent,
        in context: ModelContext
    ) throws -> Parent? {
        let parents = try syncProfile("fetch-parents") {
            try context.fetch(FetchDescriptor<Parent>())
        }
        return parents.first { $0.persistentModelID == parent.persistentModelID }
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

    private static func fetchUniqueRow<Model: SyncModelable>(
        matching identity: Model.SyncID,
        as _: Model.Type,
        in context: ModelContext
    ) throws -> Model? {
        guard let predicate = Model.syncIdentityPredicate(matching: identity) else {
            return nil
        }
        var descriptor = FetchDescriptor<Model>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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

    private static func withRelationshipLookupCache<T>(
        operation: () async throws -> T
    ) async rethrows -> T {
        let cache = SyncRelationshipLookupCache()
        return try await SyncRelationshipLookupState.$current.withValue(cache) {
            try await operation()
        }
    }

    private static func acquireSyncLease(for context: ModelContext) async -> SyncLease {
        let scopeID = ObjectIdentifier(context.container)
        return await syncLeaseRegistry.acquire(scopeID: scopeID)
    }

    private static func releaseSyncLease(_ lease: SyncLease) async {
        await syncLeaseRegistry.release(lease)
    }
}
