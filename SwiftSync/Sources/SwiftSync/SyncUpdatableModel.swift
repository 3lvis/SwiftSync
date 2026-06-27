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
    /// Hand-written conformances get a no-op default — override if your model has to-many relationships.
    /// See docs/project/ios-dirty-tracking-gap.md.
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

public struct SyncRelationshipOperations: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let insert = SyncRelationshipOperations(rawValue: 1 << 0)
    public static let update = SyncRelationshipOperations(rawValue: 1 << 1)
    public static let delete = SyncRelationshipOperations(rawValue: 1 << 2)
    public static let all: SyncRelationshipOperations = [.insert, .update, .delete]
}
