import Foundation
import SwiftData
import SwiftUI

@MainActor
@propertyWrapper
public struct SyncQuery<Model: PersistentModel>: DynamicProperty {
    @State private var publisher: SyncQueryPublisher<Model>

    public var wrappedValue: [Model] { publisher.rows }

    public init(
        _ _: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        _publisher = State(initialValue: SyncQueryPublisher(Model.self, in: syncContainer, sortBy: sortBy))
    }

    public init(
        _ _: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        _publisher = State(
            initialValue: SyncQueryPublisher(Model.self, predicate: predicate, in: syncContainer, sortBy: sortBy))
    }

    public init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, Related?>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        _publisher = State(
            initialValue: SyncQueryPublisher(
                Model.self, relationship: relationship, relationshipID: relationshipID, in: syncContainer,
                sortBy: sortBy))
    }

    public init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, [Related]>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        _publisher = State(
            initialValue: SyncQueryPublisher(
                Model.self, relationship: relationship, relationshipID: relationshipID, in: syncContainer,
                sortBy: sortBy))
    }
}
