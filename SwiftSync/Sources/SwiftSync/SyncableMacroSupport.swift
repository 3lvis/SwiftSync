import Foundation
import SwiftData

extension SwiftSync {
    @discardableResult
    public static func syncApplyToOneForeignKey<Owner, Related: PersistentModel>(
        _ owner: Owner,
        relationship: ReferenceWritableKeyPath<Owner, Related?>,
        payload: SyncPayload,
        keys: [String],
        in context: ModelContext,
        operations: SyncRelationshipOperations = .all
    ) throws -> Bool {
        _ = context
        let canClear = operations.contains(.delete)
        guard let key = payload.firstPresentKey(in: keys) else { return false }
        guard payload.value(for: key, as: NSNull.self) != nil else { return false }
        guard canClear else { return false }
        if owner[keyPath: relationship] != nil {
            owner[keyPath: relationship] = nil
            return true
        }
        return false
    }

    @discardableResult
    public static func syncApplyToOneForeignKey<Owner, Related: SyncModelable>(
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
            guard let key = payload.firstPresentKey(in: keys) else { return false }

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

            let relatedByID = try context.syncFetchRelatedRowsByIdentity(Related.self, matching: [nextID])
            guard let nextRelated = relatedByID[SwiftSync.identityKey(from: nextID)] else {
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
    public static func syncApplyToOneForeignKey<Owner, Related: PersistentModel>(
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
    public static func syncApplyToOneForeignKey<Owner, Related: SyncModelable>(
        _ owner: Owner,
        relationship: ReferenceWritableKeyPath<Owner, Related>,
        payload: SyncPayload,
        keys: [String],
        in context: ModelContext,
        operations: SyncRelationshipOperations = .all
    ) throws -> Bool {
        try syncProfile("relationship-apply-to-one-foreign-key") {
            let canLink = !operations.isDisjoint(with: [.insert, .update])
            guard let key = payload.firstPresentKey(in: keys) else { return false }

            if payload.value(for: key, as: NSNull.self) != nil {
                // Non-optional to-one relationships cannot be cleared.
                return false
            }

            guard let nextID: Related.SyncID = payload.strictValue(for: key) else {
                return false
            }

            let relatedByID = try context.syncFetchRelatedRowsByIdentity(Related.self, matching: [nextID])
            guard let nextRelated = relatedByID[SwiftSync.identityKey(from: nextID)] else {
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
    public static func syncApplyToManyForeignKeys<Owner, Related: PersistentModel>(
        _ owner: Owner,
        relationship: ReferenceWritableKeyPath<Owner, [Related]>,
        payload: SyncPayload,
        keys: [String],
        in context: ModelContext,
        operations: SyncRelationshipOperations = .all
    ) throws -> Bool {
        _ = context
        let canClear = operations.contains(.delete)
        guard let key = payload.firstPresentKey(in: keys) else { return false }

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
    public static func syncApplyToManyForeignKeys<Owner: SyncUpdatableModel, Related: SyncModelable>(
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
            guard let key = payload.firstPresentKey(in: keys) else { return false }

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
            let desiredIDs = rawIDs.syncDedupedPreservingOrder()
            let relatedByID = try context.syncFetchRelatedRowsByIdentity(Related.self, matching: desiredIDs)
            let desiredRelated = desiredIDs.compactMap { relatedByID[SwiftSync.identityKey(from: $0)] }

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
    public static func syncApplyToOneNestedObject<Owner, Related: PersistentModel>(
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
    public static func syncApplyToOneNestedObject<Owner, Related: SyncUpdatableModel>(
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
            guard let key = payload.firstPresentKey(in: keys) else { return false }

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
            var relatedByID = try context.syncFetchRelatedRowsByIdentity(Related.self)

            var resolvedRelated: Related?
            if let nestedIdentity = SwiftSync.resolveIdentityKey(from: nestedPayload, model: Related.self),
                let existing = relatedByID[nestedIdentity]
            {
                if operations.contains(.update), try existing.apply(nestedPayload) {
                    changed = true
                }
                resolvedRelated = existing
            } else if let current = owner[keyPath: relationship], operations.contains(.update),
                SwiftSync.resolveIdentityKey(from: nestedPayload, model: Related.self) == nil
            {
                if try current.apply(nestedPayload) {
                    changed = true
                }
                resolvedRelated = current
            } else if operations.contains(.insert) {
                let created = try Related.make(from: nestedPayload)
                context.insert(created)
                SyncRelationshipLookupState.current?.append(created, as: Related.self)
                if let createdIdentity = SwiftSync.resolveIdentityKey(of: created) {
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
    public static func syncApplyToManyNestedObjects<Owner, Related: PersistentModel>(
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
    public static func syncApplyToManyNestedObjects<Owner: SyncUpdatableModel, Related: SyncUpdatableModel>(
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
            guard let key = payload.firstPresentKey(in: keys) else { return false }

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
            var relatedByID = try context.syncFetchRelatedRowsByIdentity(Related.self)

            var desired: [Related] = []
            var desiredIDs: Set<PersistentIdentifier> = []
            for nestedValue in nestedValues {
                let nestedPayload = SyncPayload(values: nestedValue, keyStyle: payload.keyStyle)
                var resolved: Related?

                if let nestedIdentity = SwiftSync.resolveIdentityKey(from: nestedPayload, model: Related.self),
                    let existing = relatedByID[nestedIdentity]
                {
                    if operations.contains(.update), try existing.apply(nestedPayload) {
                        changed = true
                    }
                    resolved = existing
                } else if operations.contains(.insert) {
                    let created = try Related.make(from: nestedPayload)
                    context.insert(created)
                    SyncRelationshipLookupState.current?.append(created, as: Related.self)
                    if let createdIdentity = SwiftSync.resolveIdentityKey(of: created) {
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

    private static func syncApplyToManyRelationshipMembership<Owner, Model: PersistentModel>(
        _ owner: Owner,
        relationship: ReferenceWritableKeyPath<Owner, [Model]>,
        next: [Model],
        markChanged: (() -> Void)? = nil
    ) -> Bool {
        let current = owner[keyPath: relationship]
        guard current.syncModelIDSet != next.syncModelIDSet else { return false }
        owner[keyPath: relationship] = next
        markChanged?()
        return true
    }

    private static func mergeUnorderedRelationships<Model: PersistentModel>(
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

    public static func exportEncodeValue(_ raw: Any, dateFormatter: DateFormatter) -> Any? {
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

    public static func exportSetValue(_ value: Any, for keyPath: String, into target: inout [String: Any]) {
        let parts = keyPath.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return }
        exportSetValue(value, path: parts, into: &target)
    }

    private static func exportSetValue(_ value: Any, path: [String], into target: inout [String: Any]) {
        guard let head = path.first else { return }
        if path.count == 1 {
            target[head] = value
            return
        }
        var nested = (target[head] as? [String: Any]) ?? [:]
        exportSetValue(value, path: Array(path.dropFirst()), into: &nested)
        target[head] = nested
    }
}

/// Cycle-detection state for recursive relationship export.
/// This type is an implementation detail of `@Syncable`-generated code.
/// Do not instantiate or reference it directly.
public enum ExportState {
    private static let threadDictionaryKey = "SwiftSync.ExportState"

    /// Returns false if already visiting (cycle detected).
    public static func enter<Model: PersistentModel>(_ model: Model) -> Bool {
        let key = String(describing: model.persistentModelID)
        var visiting = currentVisiting()
        if visiting.contains(key) { return false }
        visiting.insert(key)
        saveVisiting(visiting)
        return true
    }

    public static func leave<Model: PersistentModel>(_ model: Model) {
        let key = String(describing: model.persistentModelID)
        var visiting = currentVisiting()
        visiting.remove(key)
        saveVisiting(visiting)
    }

    private static func currentVisiting() -> Set<String> {
        (Thread.current.threadDictionary[threadDictionaryKey] as? ExportStateBox)?.visiting ?? []
    }

    private static func saveVisiting(_ visiting: Set<String>) {
        Thread.current.threadDictionary[threadDictionaryKey] = ExportStateBox(visiting)
    }
}

private final class ExportStateBox {
    var visiting: Set<String>
    init(_ visiting: Set<String>) { self.visiting = visiting }
}
