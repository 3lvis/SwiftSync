import Foundation
import SwiftData

/// SwiftSync's "how far have I pushed" bookmark, one row **per model type** (not per data row). This
/// is the only durable offline state SwiftSync keeps: the change log itself is SwiftData history, and
/// this records the last-pushed `DefaultHistoryToken` so the pull can tell un-pushed local edits from
/// already-pushed ones. O(model types) rows, written once per push — no per-row, no pull-path cost.
@Model
final class SyncCursorRecord {
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
    static func storedCursor<Model>(for _: Model.Type, in context: ModelContext) -> DefaultHistoryToken? {
        let typeName = String(reflecting: Model.self)
        var descriptor = FetchDescriptor<SyncCursorRecord>(predicate: #Predicate { $0.modelTypeName == typeName })
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(DefaultHistoryToken.self, from: record.tokenData)
    }

    static func storeCursor<Model>(_ cursor: DefaultHistoryToken, for _: Model.Type, in context: ModelContext) throws {
        let typeName = String(reflecting: Model.self)
        guard let data = try? JSONEncoder().encode(cursor) else { return }
        var descriptor = FetchDescriptor<SyncCursorRecord>(predicate: #Predicate { $0.modelTypeName == typeName })
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            record.tokenData = data
        } else {
            context.insert(SyncCursorRecord(modelTypeName: typeName, tokenData: data))
        }
        try context.save()
    }
}
