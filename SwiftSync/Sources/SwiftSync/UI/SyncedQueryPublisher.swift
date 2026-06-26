import Foundation
import Observation
import SwiftData

/// Pairs a reactive **collection** query with the sync that populates it — the load-state machine +
/// observation a screen otherwise hand-wires. Declare *what* to read and *how* to load it; read back
/// live `rows` plus a `phase`. Plain-Swift and `@Observable`.
@MainActor
@Observable
public final class SyncedQueryPublisher<Model: PersistentModel> {
    @ObservationIgnored private let query: SyncQueryPublisher<Model>
    @ObservationIgnored private let driver: SyncLoadDriver

    public var phase: SyncLoadPhase { driver.phase }
    public var rows: [Model] { query.rows }

    public init(
        _ modelType: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        fallbackMessage: String = "Something went wrong. Please try again.",
        load: @escaping @MainActor () async throws -> Void
    ) {
        self.query = SyncQueryPublisher(modelType, in: syncContainer, sortBy: sortBy)
        self.driver = SyncLoadDriver(fallbackMessage: fallbackMessage, load)
    }

    public init<Related: SyncModelable>(
        _ modelType: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, Related?>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        fallbackMessage: String = "Something went wrong. Please try again.",
        load: @escaping @MainActor () async throws -> Void
    ) {
        self.query = SyncQueryPublisher(
            modelType, relationship: relationship, relationshipID: relationshipID, in: syncContainer, sortBy: sortBy)
        self.driver = SyncLoadDriver(fallbackMessage: fallbackMessage, load)
    }

    public func load() async { await driver.load() }
}
