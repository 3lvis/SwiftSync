import Foundation
import SwiftData
import SwiftSyncCore

public extension SwiftSync {
    static func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext,
        options: SyncOptions = .init()
    ) async throws {
        _ = model

        let entries = try normalize(payload: payload, model: Model.self)
        let existing = try context.fetch(FetchDescriptor<Model>())

        var index: [String: Model] = [:]
        for row in existing {
            let key = identityKey(from: row[keyPath: Model.syncIdentity])
            if index[key] != nil {
                throw SyncError.duplicateIdentity(model: String(describing: Model.self), identity: key)
            }
            index[key] = row
        }

        let rules = modeRules(options.mode)
        var changed = false

        for entry in entries {
            let payloadModel = SyncPayload(values: entry)
            let identity = try resolveIdentity(from: payloadModel, model: Model.self)
            let key = identityKey(from: identity)

            if let row = index[key] {
                guard rules.update else { continue }
                if options.dryRun { continue }
                if try row.apply(payloadModel) {
                    changed = true
                }
                continue
            }

            guard rules.insert else { continue }
            if options.dryRun { continue }
            let created = try Model.make(from: payloadModel)
            context.insert(created)
            index[key] = created
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
    ) throws -> Model.SyncID {
        for key in model.syncIdentityRemoteKeys {
            if let value = payload.value(for: key, as: Model.SyncID.self) {
                return value
            }
        }
        throw SyncError.missingIdentity(model: String(describing: model), key: model.syncIdentityRemoteKeys.joined(separator: ","))
    }

    private static func identityKey<ID: Hashable>(from identity: ID) -> String {
        String(describing: identity)
    }

    private static func modeRules(_ mode: SyncMode) -> (insert: Bool, update: Bool) {
        switch mode {
        case .upsertOnly, .fullReplace:
            return (true, true)
        case .insertOnly:
            return (true, false)
        case .updateOnly:
            return (false, true)
        case let .custom(insert, update, _):
            return (insert, update)
        }
    }
}

public extension ModelContext {
    func sync<Model: SyncUpdatableModel>(
        _ payload: [Any],
        as model: Model.Type,
        options: SyncOptions = .init()
    ) async throws {
        try await SwiftSync.sync(payload: payload, as: model, in: self, options: options)
    }
}
