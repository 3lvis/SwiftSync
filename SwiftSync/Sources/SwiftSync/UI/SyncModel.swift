import Foundation
import SwiftData
import SwiftUI

/// SwiftUI property wrapper observing the **single row** matching an id (`row`); the plain-Swift
/// equivalent is `SyncModelPublisher`, which it wraps. For a collection, use `@SyncQuery`.
@MainActor
@propertyWrapper
public struct SyncModel<Model: PersistentModel & SyncModelable>: DynamicProperty {
    @State private var publisher: SyncModelPublisher<Model>

    public var wrappedValue: Model? { publisher.row }

    public init(
        _ _: Model.Type,
        id: Model.SyncID,
        in syncContainer: SyncContainer
    ) {
        _publisher = State(initialValue: SyncModelPublisher(Model.self, id: id, in: syncContainer))
    }
}
