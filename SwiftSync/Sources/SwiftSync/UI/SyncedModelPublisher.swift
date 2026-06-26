import Foundation
import Observation
import SwiftData

/// Pairs a reactive **single-row** read (by id) with the sync that populates it — the single-row
/// counterpart of `SyncedQueryPublisher`. Plain-Swift and `@Observable`.
@MainActor
@Observable
public final class SyncedModelPublisher<Model: PersistentModel & SyncModelable> {
    @ObservationIgnored private let model: SyncModelPublisher<Model>
    @ObservationIgnored private let driver: SyncLoadDriver

    public var phase: SyncLoadPhase { driver.phase }
    public var row: Model? { model.row }

    public init(
        _ modelType: Model.Type,
        id: Model.SyncID,
        in syncContainer: SyncContainer,
        fallbackMessage: String = "Something went wrong. Please try again.",
        load: @escaping @MainActor () async throws -> Void
    ) {
        self.model = SyncModelPublisher(modelType, id: id, in: syncContainer)
        self.driver = SyncLoadDriver(fallbackMessage: fallbackMessage, load)
    }

    public func load() async { await driver.load() }
}
