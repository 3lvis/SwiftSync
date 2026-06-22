import Foundation
import SwiftData

public enum SwiftSync {
    static func normalize(payload: [Any], model: any PersistentModel.Type) throws -> [[String: Any]] {
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

    static func resolveIdentity<Model: SyncModelable>(
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

    static func syncIdentityHasUniqueAttribute<Model: SyncModelable>(_ model: Model.Type) -> Bool {
        let identityKeyPath = Model.syncIdentity as AnyKeyPath
        for propertyMetadata in Model.schemaMetadata {
            let mirror = Mirror(reflecting: propertyMetadata)
            guard let candidateKeyPath = mirror.children.first(where: { $0.label == "keypath" })?.value as? AnyKeyPath,
                candidateKeyPath == identityKeyPath
            else { continue }
            guard let rawMetadata = mirror.children.first(where: { $0.label == "metadata" })?.value else {
                return false
            }
            let metadataMirror = Mirror(reflecting: rawMetadata)
            let unwrapped: Any? =
                metadataMirror.displayStyle == .optional
                ? metadataMirror.children.first?.value
                : rawMetadata
            guard let attribute = unwrapped as? Schema.Attribute else { return false }
            return attribute.options.contains(.unique)
        }
        return false
    }

    static func identityKey<ID: Hashable>(from identity: ID) -> String {
        String(describing: identity)
    }

    static func resolveIdentityKey<Model: SyncModelable>(from payload: SyncPayload, model: Model.Type) -> String? {
        resolveIdentity(from: payload, model: model).map { identityKey(from: $0) }
    }

    static func resolveIdentityKey<Model: SyncModelable>(of row: Model) -> String? {
        identityKey(from: row[keyPath: Model.syncIdentity])
    }

    static func scopedIdentityKey<ID: Hashable>(
        from identity: ID,
        parentPersistentID: PersistentIdentifier
    ) -> String {
        "\(String(reflecting: ID.self))|\(String(describing: parentPersistentID))|\(identityKey(from: identity))"
    }

    static func fetchUniqueRow<Model: SyncModelable>(
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

    static func resolveParent<Parent: PersistentModel>(
        _ parent: Parent,
        in context: ModelContext
    ) throws -> Parent? {
        let parents = try syncPerformanceProfile(.fetchParents) {
            try context.fetch(FetchDescriptor<Parent>())
        }
        return parents.first { $0.persistentModelID == parent.persistentModelID }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let syncError = error as? SyncError, syncError == .cancelled {
            return true
        }
        return false
    }

    static func withRelationshipLookupCache<T>(
        isolation: isolated (any Actor)? = #isolation,
        operation: () async throws -> T
    ) async rethrows -> T {
        let cache = SyncRelationshipLookupCache()
        return try await SyncRelationshipLookupState.$current.withValue(cache) {
            try await operation()
        }
    }
}
