import SwiftData

public protocol ParentScopedModel: SyncUpdatableModel {
    associatedtype SyncParent: PersistentModel
    static var parentRelationship: ReferenceWritableKeyPath<Self, SyncParent?> { get }
}
