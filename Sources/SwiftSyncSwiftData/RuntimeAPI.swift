import Foundation
import SwiftData
import SwiftSyncCore

public extension SwiftSync {
    static func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext
    ) async throws {
        _ = model

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

}
