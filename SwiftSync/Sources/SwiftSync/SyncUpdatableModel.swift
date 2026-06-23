import Foundation
import SwiftData

public protocol SyncUpdatableModel: SyncModelable {
    static func make(from payload: SyncPayload) throws -> Self
    func apply(_ payload: SyncPayload) throws -> Bool
    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        isolation: isolated (any Actor)?
    ) async throws -> Bool
    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)?
    ) async throws -> Bool
    func export(keyStyle: KeyStyle, dateFormatter: DateFormatter) -> [String: Any]

    /// Forces a scalar write so iOS CoreData marks the owning row dirty after a to-many change.
    /// `@Syncable` generates `self.id = self.id`. Hand-written conformances get a no-op default
    /// — override if your model has to-many relationships. See docs/project/ios-dirty-tracking-gap.md.
    func syncMarkChanged()
}

extension SyncUpdatableModel {
    public func syncMarkChanged() {}

    public func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        false
    }

    public func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, isolation: isolation)
    }

    public func export(keyStyle _: KeyStyle, dateFormatter _: DateFormatter) -> [String: Any] {
        [:]
    }
}
