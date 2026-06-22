import Foundation
import SwiftData

public protocol SyncModelable: PersistentModel {
    associatedtype SyncID: Hashable & Codable & Sendable
    static var syncIdentity: KeyPath<Self, SyncID> { get }
    /// Swift property name of the identity (synthesised by `@Syncable`). Empty for hand-written
    /// conformances; used by `SyncContainer` to reject uniqueness constraints on non-identity fields.
    static var syncIdentityPropertyName: String { get }
    static func syncIdentityPredicate(matching identity: SyncID) -> Predicate<Self>?
    static func syncIdentityPredicate(matchingAny identities: [SyncID]) -> Predicate<Self>?
    static func syncParentPredicate(
        parentPersistentID: PersistentIdentifier,
        relationship: PartialKeyPath<Self>
    ) -> Predicate<Self>?
    static var syncIdentityRemoteKeys: [String] { get }
    static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] { get }
    static func syncRelatedModelType(for keyPath: PartialKeyPath<Self>) -> (any PersistentModel.Type)?
    static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] { get }
}

extension SyncModelable {
    public static var syncIdentityPropertyName: String { "" }
    public static var syncIdentityRemoteKeys: [String] { ["id", "remote_id", "remoteID"] }
    public static func syncIdentityPredicate(matching _: SyncID) -> Predicate<Self>? { nil }
    public static func syncIdentityPredicate(matchingAny _: [SyncID]) -> Predicate<Self>? { nil }
    public static func syncParentPredicate(
        parentPersistentID _: PersistentIdentifier,
        relationship _: PartialKeyPath<Self>
    ) -> Predicate<Self>? { nil }
    public static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] { [] }

    public static func syncRelatedModelType(for keyPath: PartialKeyPath<Self>) -> (any PersistentModel.Type)? {
        _ = keyPath
        return nil
    }

    public static var syncDefaultRefreshModelTypeNames: Set<String> {
        Set(syncDefaultRefreshModelTypes.map { String(reflecting: $0) })
    }

    public static func syncRefreshModelTypes(for keyPaths: [PartialKeyPath<Self>]) -> [any PersistentModel.Type] {
        keyPaths.compactMap { syncRelatedModelType(for: $0) }
    }

    public static func syncRefreshModelTypeNames(for keyPaths: [PartialKeyPath<Self>]) -> Set<String> {
        Set(syncRefreshModelTypes(for: keyPaths).map { String(reflecting: $0) })
    }

    public static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] { [] }
}

public struct SyncRelationshipSchemaDescriptor: Sendable {
    public let propertyName: String
    public let relatedTypeName: String
    public let isToMany: Bool
    public let hasExplicitInverseAnchor: Bool

    public init(
        propertyName: String,
        relatedTypeName: String,
        isToMany: Bool,
        hasExplicitInverseAnchor: Bool
    ) {
        self.propertyName = propertyName
        self.relatedTypeName = relatedTypeName
        self.isToMany = isToMany
        self.hasExplicitInverseAnchor = hasExplicitInverseAnchor
    }
}
