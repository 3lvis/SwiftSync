import Foundation
import SwiftData
import SwiftUI

/// The lifecycle of the sync that backs a `@SyncedQuery` / `SyncedQueryPublisher`.
public enum SyncLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

/// A query's live local rows paired with the phase of the sync that loads them.
public struct SyncedResults<Model: PersistentModel> {
    public let rows: [Model]
    public let phase: SyncLoadPhase
    public var isEmpty: Bool { rows.isEmpty }
}

/// Pairs a reactive local query with the sync that populates it — the thing every screen otherwise
/// hand-wires (a load-state machine + a publisher + observation). Declare *what* to read and *how* to
/// load it; read back live `rows` plus a `phase` (idle / loading / loaded / failed). UIKit-facing and
/// `@Observable`; the SwiftUI wrapper is `@SyncedQuery`.
@MainActor
@Observable
public final class SyncedQueryPublisher<Model: PersistentModel> {
    @ObservationIgnored private let query: SyncQueryPublisher<Model>
    @ObservationIgnored private let loadAction: @MainActor () async throws -> Void
    @ObservationIgnored private var didStart = false

    public private(set) var phase: SyncLoadPhase = .idle

    public var rows: [Model] { query.rows }
    public var results: SyncedResults<Model> { SyncedResults(rows: rows, phase: phase) }

    public init(
        _ modelType: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        load: @escaping @MainActor () async throws -> Void
    ) {
        self.query = SyncQueryPublisher(modelType, in: syncContainer, sortBy: sortBy)
        self.loadAction = load
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
        self.loadAction = load
    }

    /// Runs the load: idle/failed → loading → loaded/failed. A no-op while loading or once loaded; a prior
    /// failure is retryable.
    public func load() async {
        switch phase {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            try await loadAction()
            phase = .loaded
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
            phase = .failed(message: message)
        }
    }

    /// Kicks the load exactly once (for the SwiftUI wrapper's `update()`); safe to call on every render.
    public func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        Task { await self.load() }
    }
}

/// SwiftUI property wrapper exposing `SyncedResults` (live `rows` + sync `phase`) and auto-running the
/// load on first appearance. The UIKit/plain-Swift equivalent is `SyncedQueryPublisher`, which it wraps.
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
        // SwiftUI evaluates DynamicProperty.update() on the main actor; kick the load once on first render.
        MainActor.assumeIsolated {
            publisher.startIfNeeded()
        }
    }
}
