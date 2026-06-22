import Foundation
import SwiftData

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = context
    let canClear = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }
    guard payload.value(for: key, as: NSNull.self) != nil else { return false }
    guard canClear else { return false }
    if owner[keyPath: relationship] != nil {
        owner[keyPath: relationship] = nil
        return true
    }
    return false
}

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: SyncModelable>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    try syncProfile("relationship-apply-to-one-foreign-key") {
        let canLink = !operations.isDisjoint(with: [.insert, .update])
        let canClear = operations.contains(.delete)
        guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

        if payload.value(for: key, as: NSNull.self) != nil {
            guard canClear else { return false }
            if owner[keyPath: relationship] != nil {
                owner[keyPath: relationship] = nil
                return true
            }
            return false
        }

        guard let nextID: Related.SyncID = payload.strictValue(for: key) else {
            return false
        }

        let relatedByID = try syncFetchRelatedRowsByIdentity(Related.self, matching: [nextID], in: context)
        guard let nextRelated = relatedByID[syncIdentityKey(from: nextID)] else {
            // Old Sync parity: unknown FK row is a soft no-op.
            return false
        }

        guard canLink else { return false }
        if owner[keyPath: relationship]?.persistentModelID != nextRelated.persistentModelID {
            owner[keyPath: relationship] = nextRelated
            return true
        }
        return false
    }
}

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = owner
    _ = relationship
    _ = payload
    _ = keys
    _ = context
    _ = operations
    return false
}

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: SyncModelable>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    try syncProfile("relationship-apply-to-one-foreign-key") {
        let canLink = !operations.isDisjoint(with: [.insert, .update])
        guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

        if payload.value(for: key, as: NSNull.self) != nil {
            // Non-optional to-one relationships cannot be cleared.
            return false
        }

        guard let nextID: Related.SyncID = payload.strictValue(for: key) else {
            return false
        }

        let relatedByID = try syncFetchRelatedRowsByIdentity(Related.self, matching: [nextID], in: context)
        guard let nextRelated = relatedByID[syncIdentityKey(from: nextID)] else {
            return false
        }

        guard canLink else { return false }
        if owner[keyPath: relationship].persistentModelID != nextRelated.persistentModelID {
            owner[keyPath: relationship] = nextRelated
            return true
        }
        return false
    }
}

@discardableResult
public func syncApplyToManyForeignKeys<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = context
    let canClear = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

    if payload.value(for: key, as: NSNull.self) != nil {
        guard canClear else { return false }
        if !owner[keyPath: relationship].isEmpty {
            owner[keyPath: relationship] = []
            return true
        }
        return false
    }

    if let anyIDs: [Any] = payload.strictValue(for: key), anyIDs.isEmpty {
        guard canClear else { return false }
        if !owner[keyPath: relationship].isEmpty {
            owner[keyPath: relationship] = []
            return true
        }
    }

    return false
}

@discardableResult
public func syncApplyToManyForeignKeys<Owner: SyncUpdatableModel, Related: SyncModelable>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    try syncProfile("relationship-apply-to-many-foreign-keys") {
        let canAdd = !operations.isDisjoint(with: [.insert, .update])
        let canDelete = operations.contains(.delete)
        guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

        if payload.value(for: key, as: NSNull.self) != nil {
            guard canDelete else { return false }
            return syncApplyToManyRelationshipMembership(
                owner,
                relationship: relationship,
                next: [],
                markChanged: { owner.syncMarkChanged() }
            )
        }

        guard let rawIDs: [Related.SyncID] = payload.strictValue(for: key) else {
            return false
        }

        // Old Sync behavior avoids duplicate membership.
        let desiredIDs = dedupePreservingOrder(rawIDs)
        let relatedByID = try syncFetchRelatedRowsByIdentity(Related.self, matching: desiredIDs, in: context)
        let desiredRelated = desiredIDs.compactMap { relatedByID[syncIdentityKey(from: $0)] }

        // SwiftData does not expose ordered-relationship metadata; treat to-many as unordered membership.
        let current = owner[keyPath: relationship]
        let next = mergeUnorderedRelationships(
            current: current,
            desired: desiredRelated,
            allowDelete: canDelete,
            allowAdd: canAdd
        )
        return syncApplyToManyRelationshipMembership(
            owner,
            relationship: relationship,
            next: next,
            markChanged: { owner.syncMarkChanged() }
        )
    }
}

@discardableResult
public func syncApplyToOneNestedObject<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = owner
    _ = relationship
    _ = payload
    _ = keys
    _ = context
    _ = operations
    return false
}

@discardableResult
public func syncApplyToOneNestedObject<Owner, Related: SyncUpdatableModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    try syncProfile("relationship-apply-to-one-nested-object") {
        let canLink = !operations.isDisjoint(with: [.insert, .update])
        let canClear = operations.contains(.delete)
        guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

        if payload.value(for: key, as: NSNull.self) != nil {
            guard canClear else { return false }
            if owner[keyPath: relationship] != nil {
                owner[keyPath: relationship] = nil
                return true
            }
            return false
        }

        guard let nestedValues: [String: Any] = payload.strictValue(for: key) else {
            return false
        }
        let nestedPayload = SyncPayload(values: nestedValues, keyStyle: payload.keyStyle)
        var changed = false
        var relatedByID = try syncFetchRelatedRowsByIdentity(Related.self, in: context)

        var resolvedRelated: Related?
        if let nestedIdentity = resolveIdentity(from: nestedPayload, model: Related.self),
            let existing = relatedByID[nestedIdentity]
        {
            if operations.contains(.update), try existing.apply(nestedPayload) {
                changed = true
            }
            resolvedRelated = existing
        } else if let current = owner[keyPath: relationship], operations.contains(.update),
            resolveIdentity(from: nestedPayload, model: Related.self) == nil
        {
            if try current.apply(nestedPayload) {
                changed = true
            }
            resolvedRelated = current
        } else if operations.contains(.insert) {
            let created = try Related.make(from: nestedPayload)
            context.insert(created)
            syncRelationshipLookupCacheAppend(created, as: Related.self)
            if let createdIdentity = resolveIdentity(from: created) {
                relatedByID[createdIdentity] = created
            }
            resolvedRelated = created
            changed = true
        }

        guard canLink, let resolvedRelated else { return changed }
        if owner[keyPath: relationship]?.persistentModelID != resolvedRelated.persistentModelID {
            owner[keyPath: relationship] = resolvedRelated
            changed = true
        }
        return changed
    }
}

@discardableResult
public func syncApplyToManyNestedObjects<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = owner
    _ = relationship
    _ = payload
    _ = keys
    _ = context
    _ = operations
    return false
}

@discardableResult
public func syncApplyToManyNestedObjects<Owner: SyncUpdatableModel, Related: SyncUpdatableModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    try syncProfile("relationship-apply-to-many-nested-objects") {
        let canAdd = !operations.isDisjoint(with: [.insert, .update])
        let canDelete = operations.contains(.delete)
        guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

        if payload.value(for: key, as: NSNull.self) != nil {
            guard canDelete else { return false }
            return syncApplyToManyRelationshipMembership(
                owner,
                relationship: relationship,
                next: [],
                markChanged: { owner.syncMarkChanged() }
            )
        }

        guard let nestedValues: [[String: Any]] = payload.strictValue(for: key) else {
            return false
        }

        var changed = false
        var relatedByID = try syncFetchRelatedRowsByIdentity(Related.self, in: context)

        var desired: [Related] = []
        var desiredIDs: Set<PersistentIdentifier> = []
        for nestedValue in nestedValues {
            let nestedPayload = SyncPayload(values: nestedValue, keyStyle: payload.keyStyle)
            var resolved: Related?

            if let nestedIdentity = resolveIdentity(from: nestedPayload, model: Related.self),
                let existing = relatedByID[nestedIdentity]
            {
                if operations.contains(.update), try existing.apply(nestedPayload) {
                    changed = true
                }
                resolved = existing
            } else if operations.contains(.insert) {
                let created = try Related.make(from: nestedPayload)
                context.insert(created)
                syncRelationshipLookupCacheAppend(created, as: Related.self)
                if let createdIdentity = resolveIdentity(from: created) {
                    relatedByID[createdIdentity] = created
                }
                resolved = created
                changed = true
            }

            if let resolved, desiredIDs.insert(resolved.persistentModelID).inserted {
                desired.append(resolved)
            }
        }

        let current = owner[keyPath: relationship]
        let next = mergeUnorderedRelationships(
            current: current,
            desired: desired,
            allowDelete: canDelete,
            allowAdd: canAdd
        )

        if syncApplyToManyRelationshipMembership(
            owner,
            relationship: relationship,
            next: next,
            markChanged: { owner.syncMarkChanged() }
        ) {
            changed = true
        }

        return changed
    }
}

private func firstPresentPayloadKey(_ payload: SyncPayload, keys: [String]) -> String? {
    for key in keys where payload.contains(key) {
        return key
    }
    return nil
}

private func dedupePreservingOrder<ID: Hashable>(_ input: [ID]) -> [ID] {
    var seen: Set<ID> = []
    var output: [ID] = []
    output.reserveCapacity(input.count)
    for value in input {
        if seen.insert(value).inserted {
            output.append(value)
        }
    }
    return output
}

private func syncFetchRelatedRows<Model: PersistentModel>(
    _ modelType: Model.Type,
    in context: ModelContext
) throws -> [Model] {
    if let cache = SyncRelationshipLookupState.current {
        return try cache.rows(for: modelType, in: context)
    }
    return try syncProfile("relationship-fetch") {
        try context.fetch(FetchDescriptor<Model>())
    }
}

private func syncFetchRelatedRowsByIdentity<Model: SyncModelable>(
    _ modelType: Model.Type,
    in context: ModelContext
) throws -> [String: Model] {
    if let cache = SyncRelationshipLookupState.current {
        return try cache.rowsByIdentity(for: modelType, in: context)
    }

    let fetched = try syncFetchRelatedRows(modelType, in: context)
    return syncProfile("relationship-index-by-id") {
        let indexed: [String: Model] = Dictionary(
            uniqueKeysWithValues: fetched.compactMap { row in
                guard let identity = resolveIdentity(from: row) else { return nil }
                return (identity, row)
            }
        )
        return indexed
    }
}

private func syncFetchRelatedRowsByIdentity<Model: SyncModelable>(
    _ modelType: Model.Type,
    matching identities: [Model.SyncID],
    in context: ModelContext
) throws -> [String: Model] {
    if let cache = SyncRelationshipLookupState.current {
        return try cache.rowsByIdentity(for: modelType, matching: identities, in: context)
    }

    guard let predicate = Model.syncIdentityPredicate(matchingAny: identities) else {
        return try syncFetchRelatedRowsByIdentity(modelType, in: context)
    }

    let fetched = try syncProfile("relationship-fetch-by-identity") {
        try context.fetch(FetchDescriptor<Model>(predicate: predicate))
    }
    return syncProfile("relationship-index-by-id") {
        Dictionary(
            uniqueKeysWithValues: fetched.compactMap { row in
                guard let identity = resolveIdentity(from: row) else { return nil }
                return (identity, row)
            }
        )
    }
}

private func syncRelationshipLookupCacheAppend<Model: SyncModelable>(
    _ row: Model,
    as modelType: Model.Type
) {
    SyncRelationshipLookupState.current?.append(row, as: modelType)
}

private func syncApplyToManyRelationshipMembership<Owner, Model: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Model]>,
    next: [Model],
    markChanged: (() -> Void)? = nil
) -> Bool {
    let current = owner[keyPath: relationship]
    guard modelIDSet(current) != modelIDSet(next) else { return false }
    owner[keyPath: relationship] = next
    markChanged?()
    return true
}

private func modelIDSet<Model: PersistentModel>(_ models: [Model]) -> Set<PersistentIdentifier> {
    Set(models.map(\.persistentModelID))
}

private func mergeUnorderedRelationships<Model: PersistentModel>(
    current: [Model],
    desired: [Model],
    allowDelete: Bool,
    allowAdd: Bool
) -> [Model] {
    let desiredIDs = Set(desired.map(\.persistentModelID))

    var next: [Model]
    if allowDelete {
        next = current.filter { desiredIDs.contains($0.persistentModelID) }
    } else {
        next = current
    }

    guard allowAdd else { return next }

    let nextIDs = Set(next.map(\.persistentModelID))
    for model in desired where !nextIDs.contains(model.persistentModelID) {
        next.append(model)
    }
    return next
}

public func exportEncodeValue(_ raw: Any, dateFormatter: DateFormatter) -> Any? {
    switch raw {
    case let value as String:
        return value
    case let value as Bool:
        return value
    case let value as Int:
        return value
    case let value as Int8:
        return Int(value)
    case let value as Int16:
        return Int(value)
    case let value as Int32:
        return Int(value)
    case let value as Int64:
        return value
    case let value as UInt:
        return value
    case let value as UInt8:
        return UInt(value)
    case let value as UInt16:
        return UInt(value)
    case let value as UInt32:
        return UInt(value)
    case let value as UInt64:
        return value
    case let value as Double:
        return value
    case let value as Float:
        return value
    case let value as Decimal:
        return NSDecimalNumber(decimal: value)
    case let value as Date:
        return dateFormatter.string(from: value)
    case let value as UUID:
        return value.uuidString
    case let value as URL:
        return value.absoluteString
    case let value as Data:
        return value.base64EncodedString()
    case let value as [String]:
        return value
    case let value as [Int]:
        return value
    case let value as [Double]:
        return value
    case let value as [Bool]:
        return value
    case let value as [Any]:
        return value.compactMap { exportEncodeValue($0, dateFormatter: dateFormatter) }
    default:
        return nil
    }
}

public func exportSetValue(_ value: Any, for keyPath: String, into target: inout [String: Any]) {
    let parts = keyPath.split(separator: ".").map(String.init)
    guard !parts.isEmpty else { return }
    exportSetValue(value, path: parts, into: &target)
}

private func exportSetValue(_ value: Any, path: [String], into target: inout [String: Any]) {
    guard let head = path.first else { return }
    if path.count == 1 {
        target[head] = value
        return
    }
    var nested = (target[head] as? [String: Any]) ?? [:]
    exportSetValue(value, path: Array(path.dropFirst()), into: &nested)
    target[head] = nested
}
