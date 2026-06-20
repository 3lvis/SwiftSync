import Foundation
import SwiftData

/// SwiftSync's "how far have I pushed" bookmark, one row **per model type** (not per data row). This
/// is the only durable offline state SwiftSync keeps: the change log itself is SwiftData history, and
/// this records the last-pushed `DefaultHistoryToken` so the pull can tell un-pushed local edits from
/// already-pushed ones. O(model types) rows, written once per push — no per-row, no pull-path cost.
@Model
final class PushHistoryTokenRecord {
    @Attribute(.unique) var modelTypeName: String
    /// A JSON-encoded `DefaultHistoryToken`. Stored as `Data` because the token is a `Codable` value,
    /// not a `@Model`, so SwiftData can't persist it directly.
    var tokenData: Data

    init(modelTypeName: String, tokenData: Data) {
        self.modelTypeName = modelTypeName
        self.tokenData = tokenData
    }
}

extension SwiftSync {
    /// `push` writes `PushHistoryTokenRecord` to advance its bookmark once the upload is acknowledged.
    /// `SyncContainer` registers that model automatically; a caller who builds their own `ModelContainer`
    /// may not. Validate it's in the schema *before* the upload, so an acknowledged server write is never
    /// stranded by a token write that throws afterward.
    static func requireOfflinePushBookkeeping(in context: ModelContext) throws {
        let name = String(describing: PushHistoryTokenRecord.self)
        guard context.container.schema.entities.contains(where: { $0.name == name }) else {
            throw SyncError.schemaValidation(
                reason: """
                    Offline push needs SwiftSync's bookkeeping model (\(name)) in the context's schema, \
                    but it is missing. Build the container with SyncContainer, which registers it \
                    automatically, so an acknowledged upload is never lost to a failed token write.
                    """)
        }
    }

    static func lastPushedHistoryToken<Model>(for _: Model.Type, in context: ModelContext) -> DefaultHistoryToken? {
        let typeName = String(reflecting: Model.self)
        var descriptor = FetchDescriptor<PushHistoryTokenRecord>(predicate: #Predicate { $0.modelTypeName == typeName })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(DefaultHistoryToken.self, from: record.tokenData)
    }

    static func setLastPushedHistoryToken<Model>(
        _ token: DefaultHistoryToken, for _: Model.Type, in context: ModelContext
    )
        throws
    {
        let typeName = String(reflecting: Model.self)
        guard let data = try? JSONEncoder().encode(token) else { return }
        var descriptor = FetchDescriptor<PushHistoryTokenRecord>(predicate: #Predicate { $0.modelTypeName == typeName })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            record.tokenData = data
        } else {
            context.insert(PushHistoryTokenRecord(modelTypeName: typeName, tokenData: data))
        }
        try context.save()
    }
}
