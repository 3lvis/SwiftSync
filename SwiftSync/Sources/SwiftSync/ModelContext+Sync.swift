import Foundation
import SwiftData

extension ModelContext {
    func trimSwiftSyncInboundHistory() throws {
        let inbound = SwiftSync.inboundAuthor
        try deleteHistory(
            HistoryDescriptor<DefaultHistoryTransaction>(
                predicate: #Predicate { $0.author == inbound }))
    }

    func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as _: Model.Type,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        do {
            try Task.checkCancellation()
            try await SwiftSync.withRelationshipLookupCache {
                let dirtyPIDs = SwiftSync.offlineDirtyPersistentIDs(for: Model.self, in: self)
                let entries = try syncPerformanceProfile(.normalizePayload) {
                    try SwiftSync.normalize(payload: payload, model: Model.self)
                }
                let existing = try syncPerformanceProfile(.fetchExisting) {
                    try fetch(FetchDescriptor<Model>())
                }

                var index: [String: Model] = [:]
                var duplicates: [Model] = []
                syncPerformanceProfile(.buildIndex) {
                    for row in existing {
                        let key = SwiftSync.identityKey(from: row[keyPath: Model.syncIdentity])
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
                    try Task.checkCancellation()
                    syncPerformanceProfile(.deleteDuplicates) {
                        for duplicate in duplicates {
                            delete(duplicate)
                        }
                    }
                    changed = true
                }

                for entry in entries {
                    try Task.checkCancellation()
                    let payloadModel = SyncPayload(values: entry, keyStyle: keyStyle)
                    guard let identity = SwiftSync.resolveIdentity(from: payloadModel, model: Model.self) else {
                        continue
                    }
                    let key = SwiftSync.identityKey(from: identity)
                    seenKeys.insert(key)

                    if let row = index[key] {
                        let didApplyFields = try syncPerformanceProfile(.applyFields) {
                            try SwiftSync.applyHonoringLocalEdit(payloadModel, to: row, dirtyPIDs: dirtyPIDs)
                        }
                        if didApplyFields {
                            changed = true
                        }
                        if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                            try Task.checkCancellation()
                            let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                                try await row.applyRelationships(
                                    payloadModel,
                                    in: self,
                                    operations: relationshipOperations
                                )
                            }
                            if didApplyRelationships {
                                changed = true
                            }
                            try Task.checkCancellation()
                        }
                        continue
                    }

                    let created = try syncPerformanceProfile(.createModel) {
                        try Model.make(from: payloadModel)
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                            try await created.applyRelationships(
                                payloadModel,
                                in: self,
                                operations: relationshipOperations
                            )
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                    index[key] = created
                    changed = true
                }

                try Task.checkCancellation()
                syncPerformanceProfile(.deleteMissing) {
                    for (key, row) in index where !seenKeys.contains(key) {
                        if SwiftSync.isUnsyncedLocalInsert(row, dirtyPIDs: dirtyPIDs) { continue }
                        delete(row)
                        changed = true
                    }
                }

                try Task.checkCancellation()
                if changed {
                    try syncPerformanceProfile(.saveContext) {
                        try save()
                    }
                }
            }
        } catch {
            if SwiftSync.isCancellation(error) {
                rollback()
                throw SyncError.cancelled
            }
            throw error
        }
    }

    func sync<Model: SyncUpdatableModel>(
        item: [String: Any],
        as _: Model.Type,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        do {
            try Task.checkCancellation()
            try await SwiftSync.withRelationshipLookupCache {
                let payloadModel = syncPerformanceProfile(.normalizePayload) {
                    SyncPayload(values: item, keyStyle: keyStyle)
                }
                guard let identity = SwiftSync.resolveIdentity(from: payloadModel, model: Model.self) else {
                    return
                }
                let key = SwiftSync.identityKey(from: identity)
                var changed = false
                let matchingRow: Model?
                if SwiftSync.syncIdentityHasUniqueAttribute(Model.self),
                    Model.syncIdentityPredicate(matching: identity) != nil
                {
                    matchingRow = try syncPerformanceProfile(.fetchExistingByIdentity) {
                        try SwiftSync.fetchUniqueRow(matching: identity, as: Model.self, in: self)
                    }
                } else {
                    let existing = try syncPerformanceProfile(.fetchExisting) {
                        try fetch(FetchDescriptor<Model>())
                    }
                    matchingRow = syncPerformanceProfile(.findExisting) {
                        existing.first(where: { SwiftSync.identityKey(from: $0[keyPath: Model.syncIdentity]) == key })
                    }
                }
                if let row = matchingRow {
                    let didApplyFields = try syncPerformanceProfile(.applyFields) {
                        try row.apply(payloadModel)
                    }
                    if didApplyFields { changed = true }
                    if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                            try await row.applyRelationships(
                                payloadModel, in: self, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                } else {
                    let created = try syncPerformanceProfile(.createModel) {
                        try Model.make(from: payloadModel)
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                            try await created.applyRelationships(
                                payloadModel, in: self, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                    changed = true
                }

                try Task.checkCancellation()
                if changed {
                    try syncPerformanceProfile(.saveContext) { try save() }
                }
            }
        } catch {
            if SwiftSync.isCancellation(error) {
                rollback()
                throw SyncError.cancelled
            }
            throw error
        }
    }

    func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        item: [String: Any],
        as _: Model.Type,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        do {
            try Task.checkCancellation()
            try await SwiftSync.withRelationshipLookupCache {
                let payloadModel = syncPerformanceProfile(.normalizePayload) {
                    SyncPayload(values: item, keyStyle: keyStyle)
                }
                guard let identity = SwiftSync.resolveIdentity(from: payloadModel, model: Model.self) else {
                    return
                }
                let key = SwiftSync.identityKey(from: identity)
                let resolvedParent = try syncPerformanceProfile(
                    .resolveParent,
                    operation: {
                        try SwiftSync.resolveParent(parent, in: self)
                    })
                guard let resolvedParent else {
                    throw SyncError.invalidPayload(
                        model: String(describing: Model.self),
                        reason: "Parent must be resolved in the same ModelContext used for sync."
                    )
                }
                var changed = false
                let matchingRow: Model?
                if SwiftSync.syncIdentityHasUniqueAttribute(Model.self),
                    Model.syncIdentityPredicate(matching: identity) != nil
                {
                    matchingRow = try syncPerformanceProfile(.fetchExistingByIdentity) {
                        try SwiftSync.fetchUniqueRow(matching: identity, as: Model.self, in: self)
                    }
                } else {
                    let existing = try syncPerformanceProfile(.fetchExisting) {
                        try fetch(FetchDescriptor<Model>())
                    }
                    let scopeRows = syncPerformanceProfile(.filterScope) {
                        existing.filter {
                            $0[keyPath: relationship]?.persistentModelID == resolvedParent.persistentModelID
                        }
                    }
                    matchingRow = syncPerformanceProfile(.findExisting) {
                        scopeRows.first(where: { SwiftSync.identityKey(from: $0[keyPath: Model.syncIdentity]) == key })
                    }
                }
                if let row = matchingRow {
                    syncPerformanceProfile(.applyParent) {
                        if row[keyPath: relationship]?.persistentModelID != resolvedParent.persistentModelID {
                            row[keyPath: relationship] = resolvedParent
                            changed = true
                        }
                    }
                    let didApplyFields = try syncPerformanceProfile(.applyFields) {
                        try row.apply(payloadModel)
                    }
                    if didApplyFields { changed = true }
                    if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                            try await row.applyRelationships(
                                payloadModel, in: self, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                } else {
                    let created = try syncPerformanceProfile(.createModel) {
                        try Model.make(from: payloadModel)
                    }
                    syncPerformanceProfile(.applyParent) {
                        created[keyPath: relationship] = resolvedParent
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                            try await created.applyRelationships(
                                payloadModel, in: self, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                    changed = true
                }

                try Task.checkCancellation()
                if changed { try syncPerformanceProfile(.saveContext) { try save() } }
            }
        } catch {
            if SwiftSync.isCancellation(error) {
                rollback()
                throw SyncError.cancelled
            }
            throw error
        }
    }

    func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        payload: [Any],
        as _: Model.Type,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        keyStyle: KeyStyle = .snakeCase,
        relationshipOperations: SyncRelationshipOperations = .all,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        try await sync(
            payload: payload,
            as: Model.self,
            parent: parent,
            parentRelationship: relationship,
            isGlobal: SwiftSync.syncIdentityHasUniqueAttribute(Model.self),
            keyStyle: keyStyle,
            relationshipOperations: relationshipOperations
        )
    }

    private func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        payload: [Any],
        as _: Model.Type,
        parent: Parent,
        parentRelationship: ReferenceWritableKeyPath<Model, Parent?>,
        isGlobal: Bool,
        keyStyle: KeyStyle,
        relationshipOperations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
    ) async throws {
        do {
            try Task.checkCancellation()
            try await SwiftSync.withRelationshipLookupCache {
                let dirtyPIDs = SwiftSync.offlineDirtyPersistentIDs(for: Model.self, in: self)
                let entries = try syncPerformanceProfile(.normalizePayload) {
                    try SwiftSync.normalize(payload: payload, model: Model.self)
                }
                let resolvedParent = try syncPerformanceProfile(
                    .resolveParent,
                    operation: {
                        try SwiftSync.resolveParent(parent, in: self)
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
                    scopeRows = try syncPerformanceProfile(.fetchExistingByParent) {
                        try fetch(FetchDescriptor<Model>(predicate: parentPredicate))
                    }
                } else {
                    let fetchedExisting = try syncPerformanceProfile(.fetchExisting) {
                        try fetch(FetchDescriptor<Model>())
                    }
                    scopeRows = syncPerformanceProfile(.filterScope) {
                        fetchedExisting.filter {
                            $0[keyPath: parentRelationship]?.persistentModelID == resolvedParent.persistentModelID
                        }
                    }
                }

                var index: [String: Model] = [:]
                var duplicates: [Model] = []
                syncPerformanceProfile(.buildIndex) {
                    if isGlobal {
                        for row in scopeRows {
                            let key = SwiftSync.identityKey(from: row[keyPath: Model.syncIdentity])
                            if index[key] != nil {
                                duplicates.append(row)
                                continue
                            }
                            index[key] = row
                        }
                    } else {
                        for row in scopeRows {
                            let key = SwiftSync.scopedIdentityKey(
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
                    try Task.checkCancellation()
                    syncPerformanceProfile(.deleteDuplicates) {
                        for duplicate in duplicates {
                            delete(duplicate)
                        }
                    }
                    changed = true
                }

                for entry in entries {
                    try Task.checkCancellation()
                    let payloadModel = SyncPayload(values: entry, keyStyle: keyStyle)
                    guard let identity = SwiftSync.resolveIdentity(from: payloadModel, model: Model.self) else {
                        continue
                    }
                    let key: String
                    if isGlobal {
                        key = SwiftSync.identityKey(from: identity)
                    } else {
                        key = SwiftSync.scopedIdentityKey(
                            from: identity,
                            parentPersistentID: resolvedParent.persistentModelID
                        )
                    }
                    seenKeys.insert(key)

                    if let row = index[key] {
                        syncPerformanceProfile(.applyParent) {
                            if row[keyPath: parentRelationship]?.persistentModelID != resolvedParent.persistentModelID {
                                row[keyPath: parentRelationship] = resolvedParent
                                changed = true
                            }
                        }
                        let didApplyFields = try syncPerformanceProfile(.applyFields) {
                            try SwiftSync.applyHonoringLocalEdit(payloadModel, to: row, dirtyPIDs: dirtyPIDs)
                        }
                        if didApplyFields {
                            changed = true
                        }
                        if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                            try Task.checkCancellation()
                            let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                                try await row.applyRelationships(
                                    payloadModel,
                                    in: self,
                                    operations: relationshipOperations
                                )
                            }
                            if didApplyRelationships {
                                changed = true
                            }
                            try Task.checkCancellation()
                        }
                        continue
                    }

                    if isGlobal {
                        let movedRow = try syncPerformanceProfile(
                            .fetchExistingByIdentity,
                            operation: {
                                try SwiftSync.fetchUniqueRow(matching: identity, as: Model.self, in: self)
                            })
                        if let movedRow {
                            syncPerformanceProfile(.applyParent) {
                                if movedRow[keyPath: parentRelationship]?.persistentModelID
                                    != resolvedParent.persistentModelID
                                {
                                    movedRow[keyPath: parentRelationship] = resolvedParent
                                    changed = true
                                }
                            }
                            let didApplyFields = try syncPerformanceProfile(.applyFields) {
                                try SwiftSync.applyHonoringLocalEdit(payloadModel, to: movedRow, dirtyPIDs: dirtyPIDs)
                            }
                            if didApplyFields {
                                changed = true
                            }
                            if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                                try Task.checkCancellation()
                                let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                                    try await movedRow.applyRelationships(
                                        payloadModel,
                                        in: self,
                                        operations: relationshipOperations
                                    )
                                }
                                if didApplyRelationships {
                                    changed = true
                                }
                                try Task.checkCancellation()
                            }
                            index[key] = movedRow
                            continue
                        }
                    }

                    let created = try syncPerformanceProfile(.createModel) {
                        try Model.make(from: payloadModel)
                    }
                    syncPerformanceProfile(.applyParent) {
                        created[keyPath: parentRelationship] = resolvedParent
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncPerformanceProfile(.applyRelationships) {
                            try await created.applyRelationships(
                                payloadModel,
                                in: self,
                                operations: relationshipOperations
                            )
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                    index[key] = created
                    changed = true
                }

                try Task.checkCancellation()
                syncPerformanceProfile(.deleteMissing) {
                    for row in scopeRows {
                        let key: String
                        if isGlobal {
                            key = SwiftSync.identityKey(from: row[keyPath: Model.syncIdentity])
                        } else {
                            key = SwiftSync.scopedIdentityKey(
                                from: row[keyPath: Model.syncIdentity],
                                parentPersistentID: resolvedParent.persistentModelID
                            )
                        }
                        if seenKeys.contains(key) {
                            continue
                        }
                        if SwiftSync.isUnsyncedLocalInsert(row, dirtyPIDs: dirtyPIDs) {
                            continue
                        }
                        delete(row)
                        changed = true
                    }
                }

                try Task.checkCancellation()
                if changed {
                    try syncPerformanceProfile(.saveContext) {
                        try save()
                    }
                }
            }
        } catch {
            if SwiftSync.isCancellation(error) {
                rollback()
                throw SyncError.cancelled
            }
            throw error
        }
    }
}

extension ModelContext {
    private func syncFetchRelatedRows<Model: PersistentModel>(_ modelType: Model.Type) throws -> [Model] {
        if let cache = SyncRelationshipLookupState.current {
            return try cache.rows(for: modelType, in: self)
        }
        return try syncPerformanceProfile(.relationshipFetch) {
            try fetch(FetchDescriptor<Model>())
        }
    }

    func syncFetchRelatedRowsByIdentity<Model: SyncModelable>(_ modelType: Model.Type) throws -> [String: Model] {
        if let cache = SyncRelationshipLookupState.current {
            return try cache.rowsByIdentity(for: modelType, in: self)
        }
        let fetched = try syncFetchRelatedRows(modelType)
        return syncPerformanceProfile(.relationshipIndexByID) {
            Dictionary(
                uniqueKeysWithValues: fetched.compactMap { row in
                    guard let identity = SwiftSync.resolveIdentityKey(of: row) else { return nil }
                    return (identity, row)
                }
            )
        }
    }

    func syncFetchRelatedRowsByIdentity<Model: SyncModelable>(
        _ modelType: Model.Type, matching identities: [Model.SyncID]
    ) throws -> [String: Model] {
        if let cache = SyncRelationshipLookupState.current {
            return try cache.rowsByIdentity(for: modelType, matching: identities, in: self)
        }
        guard let predicate = Model.syncIdentityPredicate(matchingAny: identities) else {
            return try syncFetchRelatedRowsByIdentity(modelType)
        }
        let fetched = try syncPerformanceProfile(.relationshipFetchByIdentity) {
            try fetch(FetchDescriptor<Model>(predicate: predicate))
        }
        return syncPerformanceProfile(.relationshipIndexByID) {
            Dictionary(
                uniqueKeysWithValues: fetched.compactMap { row in
                    guard let identity = SwiftSync.resolveIdentityKey(of: row) else { return nil }
                    return (identity, row)
                }
            )
        }
    }
}
