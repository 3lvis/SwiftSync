import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class SyncModelPublisher<Model: PersistentModel & SyncModelable> {

    public private(set) var row: Model?

    @ObservationIgnored private let syncContainer: SyncContainer
    @ObservationIgnored private let id: Model.SyncID
    @ObservationIgnored private let observedModelTypeNames: Set<String>
    @ObservationIgnored nonisolated(unsafe) private var notificationToken: NSObjectProtocol?

    public init(
        _ _: Model.Type,
        id: Model.SyncID,
        in syncContainer: SyncContainer
    ) {
        self.syncContainer = syncContainer
        self.id = id
        self.observedModelTypeNames = Self.defaultObservedModelTypeNames()
        notificationToken = NotificationCenter.default.addObserver(
            forName: SyncContainer.didSaveChangesNotification,
            object: syncContainer,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedTypeNames = syncQueryChangedModelTypeNames(from: notification.userInfo)
            let changedIDs = syncQueryChangedIdentifiers(from: notification.userInfo)
            MainActor.assumeIsolated {
                guard self.shouldReload(changedTypeNames: changedTypeNames, changedIDs: changedIDs) else { return }
                self.reload()
            }
        }
        reload()
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    private func shouldReload(
        changedTypeNames: Set<String>,
        changedIDs: Set<PersistentIdentifier>
    ) -> Bool {
        if changedTypeNames.isEmpty {
            return true
        }
        if !observedModelTypeNames.isDisjoint(with: changedTypeNames) {
            return true
        }

        guard let loadedRow = row else { return false }
        return changedIDs.contains(loadedRow.persistentModelID)
    }

    private func reload() {
        do {
            let rows = try syncContainer.mainContext.fetch(FetchDescriptor<Model>())
            let fetchedRow = rows.first { $0[keyPath: Model.syncIdentity] == id }
            withMutation(keyPath: \.row) {
                _row = fetchedRow
            }
        } catch {
            withMutation(keyPath: \.row) {
                _row = nil
            }
        }
    }

    private static func defaultObservedModelTypeNames() -> Set<String> {
        var names = Model.syncDefaultRefreshModelTypeNames
        names.insert(String(reflecting: Model.self))
        return names
    }
}
