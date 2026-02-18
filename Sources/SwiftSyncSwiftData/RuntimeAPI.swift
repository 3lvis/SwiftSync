import Foundation
import SwiftData
import SwiftSyncCore

public extension SwiftSync {
    static func sync<Model: PersistentModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext,
        options: SyncOptions = .init()
    ) async throws {
        _ = (context, options)
        _ = (payload, model)
    }
}

public extension ModelContext {
    func sync<Model: PersistentModel>(
        _ payload: [Any],
        as model: Model.Type,
        options: SyncOptions = .init()
    ) async throws {
        try await SwiftSync.sync(payload: payload, as: model, in: self, options: options)
    }
}
