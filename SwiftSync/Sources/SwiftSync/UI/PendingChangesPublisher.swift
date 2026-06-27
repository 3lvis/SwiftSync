import Foundation
import Observation
import SwiftData

/// The reactive counterpart of `SwiftSync.pendingChanges(for:in:)`: exposes the un-pushed changes for
/// `Model`, re-evaluated whenever the store saves. Plain-Swift and `@Observable`.
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
