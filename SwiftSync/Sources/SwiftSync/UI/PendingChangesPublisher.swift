import Foundation
import Observation
import SwiftData

/// Observes the local store and exposes the **pending changes** for `Model` — the un-pushed inserts/
/// updates/deletes since the last push — the reactive counterpart of `SwiftSync.pendingChanges(for:in:)`.
/// `pendingChanges` is computed against the live store on each read (so a synchronous read right after a
/// save is current); reading it inside an observation also re-evaluates whenever the store saves.
/// Plain-Swift and `@Observable`.
@MainActor
@Observable
public final class PendingChangesPublisher<Model: SyncUpdatableModel> where Model.SyncID == String {
    @ObservationIgnored private let syncContainer: SyncContainer
    @ObservationIgnored nonisolated(unsafe) private var notificationToken: NSObjectProtocol?
    private var revision = 0

    public init(_ modelType: Model.Type, in syncContainer: SyncContainer) {
        self.syncContainer = syncContainer
        notificationToken = NotificationCenter.default.addObserver(
            forName: SyncContainer.didSaveChangesNotification,
            object: syncContainer,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision &+= 1 }
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    public var pendingChanges: SyncPendingChanges {
        _ = revision
        return (try? SwiftSync.pendingChanges(for: Model.self, in: syncContainer.mainContext))
            ?? SyncPendingChanges(inserts: [], updates: [], deletes: [])
    }
}
