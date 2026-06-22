import Foundation
import SwiftData

extension ModelContext {
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
                let entries = try syncProfile("normalize-payload") {
                    try SwiftSync.normalize(payload: payload, model: Model.self)
                }
                let existing = try syncProfile("fetch-existing") {
                    try fetch(FetchDescriptor<Model>())
                }

                var index: [String: Model] = [:]
                var duplicates: [Model] = []
                syncProfile("build-index") {
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
                    syncProfile("delete-duplicates") {
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
                        let didApplyFields = try syncProfile("apply-fields") {
                            try SwiftSync.applyHonoringLocalEdit(payloadModel, to: row, dirtyPIDs: dirtyPIDs)
                        }
                        if didApplyFields {
                            changed = true
                        }
                        if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                            try Task.checkCancellation()
                            let didApplyRelationships = try await syncProfile("apply-relationships") {
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

                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
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
                syncProfile("delete-missing") {
                    for (key, row) in index where !seenKeys.contains(key) {
                        if SwiftSync.isUnsyncedLocalInsert(row, dirtyPIDs: dirtyPIDs) { continue }
                        delete(row)
                        changed = true
                    }
                }

                try Task.checkCancellation()
                if changed {
                    try syncProfile("save-context") {
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
                let payloadModel = syncProfile("normalize-payload") {
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
                    matchingRow = try syncProfile("fetch-existing-by-identity") {
                        try SwiftSync.fetchUniqueRow(matching: identity, as: Model.self, in: self)
                    }
                } else {
                    let existing = try syncProfile("fetch-existing") {
                        try fetch(FetchDescriptor<Model>())
                    }
                    matchingRow = syncProfile("find-existing") {
                        existing.first(where: { SwiftSync.identityKey(from: $0[keyPath: Model.syncIdentity]) == key })
                    }
                }
                if let row = matchingRow {
                    let didApplyFields = try syncProfile("apply-fields") {
                        try row.apply(payloadModel)
                    }
                    if didApplyFields { changed = true }
                    if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await row.applyRelationships(
                                payloadModel, in: self, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                } else {
                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
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
                    try syncProfile("save-context") { try save() }
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
                let payloadModel = syncProfile("normalize-payload") {
                    SyncPayload(values: item, keyStyle: keyStyle)
                }
                guard let identity = SwiftSync.resolveIdentity(from: payloadModel, model: Model.self) else {
                    return
                }
                let key = SwiftSync.identityKey(from: identity)
                let resolvedParent = try syncProfile(
                    "resolve-parent",
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
                    matchingRow = try syncProfile("fetch-existing-by-identity") {
                        try SwiftSync.fetchUniqueRow(matching: identity, as: Model.self, in: self)
                    }
                } else {
                    let existing = try syncProfile("fetch-existing") {
                        try fetch(FetchDescriptor<Model>())
                    }
                    let scopeRows = syncProfile("filter-scope") {
                        existing.filter {
                            $0[keyPath: relationship]?.persistentModelID == resolvedParent.persistentModelID
                        }
                    }
                    matchingRow = syncProfile("find-existing") {
                        scopeRows.first(where: { SwiftSync.identityKey(from: $0[keyPath: Model.syncIdentity]) == key })
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
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
                            try await row.applyRelationships(
                                payloadModel, in: self, operations: relationshipOperations)
                        }
                        if didApplyRelationships {
                            changed = true
                        }
                        try Task.checkCancellation()
                    }
                } else {
                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    syncProfile("apply-parent") {
                        created[keyPath: relationship] = resolvedParent
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
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
                if changed { try syncProfile("save-context") { try save() } }
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
                let entries = try syncProfile("normalize-payload") {
                    try SwiftSync.normalize(payload: payload, model: Model.self)
                }
                let resolvedParent = try syncProfile(
                    "resolve-parent",
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
                    scopeRows = try syncProfile("fetch-existing-by-parent") {
                        try fetch(FetchDescriptor<Model>(predicate: parentPredicate))
                    }
                } else {
                    let fetchedExisting = try syncProfile("fetch-existing") {
                        try fetch(FetchDescriptor<Model>())
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
                    syncProfile("delete-duplicates") {
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
                        syncProfile("apply-parent") {
                            if row[keyPath: parentRelationship]?.persistentModelID != resolvedParent.persistentModelID {
                                row[keyPath: parentRelationship] = resolvedParent
                                changed = true
                            }
                        }
                        let didApplyFields = try syncProfile("apply-fields") {
                            try SwiftSync.applyHonoringLocalEdit(payloadModel, to: row, dirtyPIDs: dirtyPIDs)
                        }
                        if didApplyFields {
                            changed = true
                        }
                        if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                            try Task.checkCancellation()
                            let didApplyRelationships = try await syncProfile("apply-relationships") {
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
                        let movedRow = try syncProfile(
                            "fetch-existing-by-identity",
                            operation: {
                                try SwiftSync.fetchUniqueRow(matching: identity, as: Model.self, in: self)
                            })
                        if let movedRow {
                            syncProfile("apply-parent") {
                                if movedRow[keyPath: parentRelationship]?.persistentModelID
                                    != resolvedParent.persistentModelID
                                {
                                    movedRow[keyPath: parentRelationship] = resolvedParent
                                    changed = true
                                }
                            }
                            let didApplyFields = try syncProfile("apply-fields") {
                                try SwiftSync.applyHonoringLocalEdit(payloadModel, to: movedRow, dirtyPIDs: dirtyPIDs)
                            }
                            if didApplyFields {
                                changed = true
                            }
                            if !relationshipOperations.isDisjoint(with: [.update, .delete]) {
                                try Task.checkCancellation()
                                let didApplyRelationships = try await syncProfile("apply-relationships") {
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

                    let created = try syncProfile("create-model") {
                        try Model.make(from: payloadModel)
                    }
                    syncProfile("apply-parent") {
                        created[keyPath: parentRelationship] = resolvedParent
                    }
                    insert(created)
                    if relationshipOperations.contains(.insert) {
                        try Task.checkCancellation()
                        let didApplyRelationships = try await syncProfile("apply-relationships") {
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
                syncProfile("delete-missing") {
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
                    try syncProfile("save-context") {
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
