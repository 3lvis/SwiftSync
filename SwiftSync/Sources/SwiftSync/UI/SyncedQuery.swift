import Foundation
import SwiftData
import SwiftUI

/// The lifecycle of the sync that backs a synced read.
public enum SyncLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)

    /// The failure message, if this phase is `.failed`.
    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Drives one load action through the phases. Shared by the query and model synced publishers so the
/// load/observe logic lives in exactly one place.
@MainActor
@Observable
final class SyncLoadDriver {
    @ObservationIgnored private let action: @MainActor () async throws -> Void
    @ObservationIgnored private var didStart = false
    private(set) var phase: SyncLoadPhase = .idle

    init(_ action: @escaping @MainActor () async throws -> Void) {
        self.action = action
    }

    func load() async {
        switch phase {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            try await action()
            phase = .loaded
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
            phase = .failed(message: message)
        }
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        Task { await self.load() }
    }
}

/// A query's live local rows paired with the phase of the sync that loads them.
public struct SyncedResults<Model: PersistentModel> {
    public let rows: [Model]
    public let phase: SyncLoadPhase
    public var isEmpty: Bool { rows.isEmpty }
}

/// Pairs a reactive **collection** query with the sync that populates it — the load-state machine +
/// observation a screen otherwise hand-wires. Declare *what* to read and *how* to load it; read back
/// live `rows` plus a `phase`. UIKit-facing and `@Observable`; the SwiftUI wrapper is `@SyncedQuery`.
@MainActor
@Observable
public final class SyncedQueryPublisher<Model: PersistentModel> {
    @ObservationIgnored private let query: SyncQueryPublisher<Model>
    @ObservationIgnored private let driver: SyncLoadDriver

    public var phase: SyncLoadPhase { driver.phase }
    public var rows: [Model] { query.rows }
    public var results: SyncedResults<Model> { SyncedResults(rows: rows, phase: phase) }

    public init(
        _ modelType: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        load: @escaping @MainActor () async throws -> Void
    ) {
        self.query = SyncQueryPublisher(modelType, in: syncContainer, sortBy: sortBy)
        self.driver = SyncLoadDriver(load)
    }

    public init<Related: SyncModelable>(
        _ modelType: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, Related?>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        load: @escaping @MainActor () async throws -> Void
    ) {
        self.query = SyncQueryPublisher(
            modelType, relationship: relationship, relationshipID: relationshipID, in: syncContainer, sortBy: sortBy)
        self.driver = SyncLoadDriver(load)
    }

    public func load() async { await driver.load() }
    public func startIfNeeded() { driver.startIfNeeded() }
}

/// Pairs a reactive **single-row** read (by id) with the sync that populates it. UIKit-facing and
/// `@Observable`; the SwiftUI wrapper is `@SyncedModel`.
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
        load: @escaping @MainActor () async throws -> Void
    ) {
        self.model = SyncModelPublisher(modelType, id: id, in: syncContainer)
        self.driver = SyncLoadDriver(load)
    }

    public func load() async { await driver.load() }
    public func startIfNeeded() { driver.startIfNeeded() }
}

/// SwiftUI property wrapper exposing `SyncedResults` (live `rows` + sync `phase`), auto-running the load
/// on first appearance. The UIKit/plain-Swift equivalent is `SyncedQueryPublisher`, which it wraps.
@MainActor
@propertyWrapper
public struct SyncedQuery<Model: PersistentModel>: DynamicProperty {
    @State private var publisher: SyncedQueryPublisher<Model>

    public var wrappedValue: SyncedResults<Model> { publisher.results }

    public init(
        _ modelType: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        load: @escaping @MainActor () async throws -> Void
    ) {
        _publisher = State(
            initialValue: SyncedQueryPublisher(modelType, in: syncContainer, sortBy: sortBy, load: load))
    }

    public init<Related: SyncModelable>(
        _ modelType: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, Related?>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        load: @escaping @MainActor () async throws -> Void
    ) {
        _publisher = State(
            initialValue: SyncedQueryPublisher(
                modelType, relationship: relationship, relationshipID: relationshipID, in: syncContainer,
                sortBy: sortBy, load: load))
    }

    public nonisolated func update() {
        MainActor.assumeIsolated { publisher.startIfNeeded() }
    }
}

/// SwiftUI property wrapper exposing the single row matching an id plus the sync `phase`, auto-running
/// the load on first appearance. The UIKit/plain-Swift equivalent is `SyncedModelPublisher`.
@MainActor
@propertyWrapper
public struct SyncedModel<Model: PersistentModel & SyncModelable>: DynamicProperty {
    @State private var publisher: SyncedModelPublisher<Model>

    public var wrappedValue: Model? { publisher.row }
    public var phase: SyncLoadPhase { publisher.phase }

    public init(
        _ modelType: Model.Type,
        id: Model.SyncID,
        in syncContainer: SyncContainer,
        load: @escaping @MainActor () async throws -> Void
    ) {
        _publisher = State(initialValue: SyncedModelPublisher(modelType, id: id, in: syncContainer, load: load))
    }

    public nonisolated func update() {
        MainActor.assumeIsolated { publisher.startIfNeeded() }
    }
}
