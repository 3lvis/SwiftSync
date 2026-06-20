import Foundation
import Observation
import SwiftData

/// How an app pushes a model's pending changes to its backend. Registered once per offline model with
/// `SyncEngine.register(_:for:)`; the engine calls `push` whenever it drains the queue. The closure owns
/// the network call and returns only the rejected rows (everything else is confirmed) — the same contract
/// as `SwiftSync.withPendingChanges`'s `process` closure, promoted to a registered object.
public protocol SyncBackend: Sendable {
    func push(_ pending: SyncPendingChanges) async throws -> [SyncPushFailure]
}

/// The outbound-sync driver: owns the queue-drain, reconnect handling, de-duplication, and the
/// observable pending/failed counts a UI binds to. Wraps a `SyncContainer` (the `Sendable` store
/// primitive) and runs on the main actor so its observable state is safe to read from SwiftUI.
///
/// An app registers one `SyncBackend` per offline model, feeds reachability via `isOnline`, and reads
/// `pendingCount` / `failedCount` / `failures`. It never hand-writes the drain or reconnect loop.
@MainActor
@Observable
public final class SyncEngine {
    public let container: SyncContainer

    /// App-fed reachability. Flipping offline→online drains the queue automatically.
    public var isOnline: Bool {
        didSet {
            if isOnline && !oldValue { scheduleDrain() }
        }
    }

    public private(set) var isSyncing = false
    public private(set) var pendingCount = 0
    public private(set) var failedCount = 0
    /// The rejected rows from the most recent drain. The app maps these ids to its own inbox.
    public private(set) var failures: [SyncPushFailure] = []

    @ObservationIgnored private var registrations: [Registration] = []
    /// The in-flight reconnect drain, if any — exposed so callers (and tests) can await it.
    @ObservationIgnored private(set) var inFlightDrain: Task<Void, Never>?

    public init(_ container: SyncContainer, isOnline: Bool = true) {
        self.container = container
        self.isOnline = isOnline
    }

    /// Register how an offline model pushes. Call once per pushable model at setup.
    public func register<Model: SyncUpdatableModel>(_ backend: SyncBackend, for _: Model.Type)
    where Model.SyncID == String {
        let container = self.container
        registrations.append(
            Registration(
                drain: {
                    try await SwiftSync.withPendingChanges(for: Model.self, in: container.mainContext) {
                        pending in
                        try await backend.push(pending)
                    }
                },
                pendingIDs: {
                    let pending = try SwiftSync.pendingChanges(for: Model.self, in: container.mainContext)
                    return pending.inserts + pending.updates + pending.deletes
                }))
    }

    /// Drain the pending queue for every registered model through its backend. A no-op while offline or
    /// when a drain is already running. Refreshes counts and `failures` afterward. Per-model errors are
    /// swallowed: the rows simply stay pending and are retried next drain.
    public func drain() async {
        guard isOnline, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var collected: [SyncPushFailure] = []
        for registration in registrations {
            if let modelFailures = try? await registration.drain() {
                collected += modelFailures
            }
        }
        failures = collected
        refreshCounts()
    }

    /// Recompute `pendingCount` / `failedCount` from the store + the last drain's failures. Cheap; safe
    /// to call after any local write so a UI badge stays current. A failed row reads as failed, not
    /// pending, so it is not double-counted.
    public func refreshCounts() {
        let failedIDs = Set(failures.map(\.id))
        var pending: [String] = []
        for registration in registrations {
            pending += (try? registration.pendingIDs()) ?? []
        }
        pendingCount = pending.filter { !failedIDs.contains($0) }.count
        failedCount = failures.count
    }

    private func scheduleDrain() {
        inFlightDrain = Task { [weak self] in await self?.drain() }
    }

    private struct Registration {
        let drain: @MainActor () async throws -> [SyncPushFailure]
        let pendingIDs: @MainActor () throws -> [String]
    }
}
