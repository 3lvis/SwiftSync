import Foundation
import SwiftData
import SwiftUI

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
