import Foundation
import SwiftData

final class SyncRelationshipLookupCache: @unchecked Sendable {
    private var rowsByType: [ObjectIdentifier: Any] = [:]
    private var rowsByIdentityType: [ObjectIdentifier: Any] = [:]
    // Partial identity maps from id-narrowed fetches. Kept separate from the full-table
    // `rowsByIdentityType` so a partial map is never mistaken for a complete one.
    private var narrowedRowsByIdentityType: [ObjectIdentifier: Any] = [:]

    func rows<Model: PersistentModel>(
        for modelType: Model.Type,
        in context: ModelContext
    ) throws -> [Model] {
        let key = ObjectIdentifier(modelType)
        if let cached = rowsByType[key] as? [Model] {
            return cached
        }

        let fetched = try syncProfile("relationship-fetch") {
            try context.fetch(FetchDescriptor<Model>())
        }
        rowsByType[key] = fetched
        return fetched
    }

    func rowsByIdentity<Model: SyncModelable>(
        for modelType: Model.Type,
        in context: ModelContext
    ) throws -> [String: Model] {
        let key = ObjectIdentifier(modelType)
        if let cached = rowsByIdentityType[key] as? [String: Model] {
            return cached
        }

        let fetched = try rows(for: modelType, in: context)
        let indexed: [String: Model] = syncProfile("relationship-index-by-id") {
            Dictionary(
                uniqueKeysWithValues: fetched.compactMap { row in
                    guard let identity = SwiftSync.resolveIdentityKey(of: row) else { return nil }
                    return (identity, row)
                }
            )
        }
        rowsByIdentityType[key] = indexed
        return indexed
    }

    func rowsByIdentity<Model: SyncModelable>(
        for modelType: Model.Type,
        matching identities: [Model.SyncID],
        in context: ModelContext
    ) throws -> [String: Model] {
        let key = ObjectIdentifier(modelType)
        var map = (narrowedRowsByIdentityType[key] as? [String: Model]) ?? [:]

        // Unresolved ids are intentionally not memoized: a later pass may have inserted them,
        // and the re-fetch is a narrow predicate query over the few still-missing ids.
        let missing = identities.filter { map[SwiftSync.identityKey(from: $0)] == nil }
        guard !missing.isEmpty else { return map }

        guard let predicate = Model.syncIdentityPredicate(matchingAny: missing) else {
            return try rowsByIdentity(for: modelType, in: context)
        }

        let fetched = try syncProfile("relationship-fetch-by-identity") {
            try context.fetch(FetchDescriptor<Model>(predicate: predicate))
        }
        syncProfile("relationship-index-by-id") {
            for row in fetched {
                if let identity = SwiftSync.resolveIdentityKey(of: row) {
                    map[identity] = row
                }
            }
        }
        narrowedRowsByIdentityType[key] = map
        return map
    }

    func append<Model: SyncModelable>(_ row: Model, as modelType: Model.Type) {
        let key = ObjectIdentifier(modelType)
        if var cached = rowsByType[key] as? [Model] {
            cached.append(row)
            rowsByType[key] = cached
        }
        if let identity = SwiftSync.resolveIdentityKey(of: row) {
            if var cached = rowsByIdentityType[key] as? [String: Model] {
                cached[identity] = row
                rowsByIdentityType[key] = cached
            }
            if var cached = narrowedRowsByIdentityType[key] as? [String: Model] {
                cached[identity] = row
                narrowedRowsByIdentityType[key] = cached
            }
        }
    }
}

enum SyncRelationshipLookupState {
    @TaskLocal static var current: SyncRelationshipLookupCache?
}
