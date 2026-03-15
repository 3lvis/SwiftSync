import Foundation
import Observation
import SwiftData

// Observation callbacks are dispatched on queue: .main.
@MainActor
@Observable
public final class SyncQueryPublisher<Model: PersistentModel> {

    // MARK: - Public interface

    public private(set) var rows: [Model] = []

    // MARK: - Private state

    @ObservationIgnored private let syncContainer: SyncContainer
    @ObservationIgnored private let predicate: Predicate<Model>?
    @ObservationIgnored private let sortBy: [SortDescriptor<Model>]
    @ObservationIgnored private let postFetchFilter: ((Model) -> Bool)?
    @ObservationIgnored private let observedModelTypeNames: Set<String>
    @ObservationIgnored nonisolated(unsafe) private var notificationToken: NSObjectProtocol?

    // MARK: - Designated init

    private init(
        syncContainer: SyncContainer,
        predicate: Predicate<Model>?,
        sortBy: [SortDescriptor<Model>],
        postFetchFilter: ((Model) -> Bool)?
    ) {
        self.syncContainer = syncContainer
        self.predicate = predicate
        self.sortBy = sortBy
        self.postFetchFilter = postFetchFilter
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

    // MARK: - Public inits

    public convenience init(
        _ _: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.init(syncContainer: syncContainer, predicate: nil, sortBy: sortBy, postFetchFilter: nil)
    }

    public convenience init(
        _ _: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.init(syncContainer: syncContainer, predicate: predicate, sortBy: sortBy, postFetchFilter: nil)
    }

    public convenience init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, Related?>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: { row in
                guard let related = row[keyPath: relationship] else { return false }
                return related[keyPath: Related.syncIdentity] == relationshipID
            }
        )
    }

    public convenience init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, [Related]>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: { row in
                row[keyPath: relationship].contains { $0[keyPath: Related.syncIdentity] == relationshipID }
            }
        )
    }

    // MARK: - Private

    private func shouldReload(
        changedTypeNames: Set<String>,
        changedIDs: Set<PersistentIdentifier>
    ) -> Bool {
        if changedTypeNames.isEmpty { return true }
        if !observedModelTypeNames.isDisjoint(with: changedTypeNames) { return true }
        if changedIDs.isEmpty { return false }
        return !Set(rows.map(\.persistentModelID)).isDisjoint(with: changedIDs)
    }

    private func reload() {
        let descriptor = predicate.map { FetchDescriptor(predicate: $0, sortBy: sortBy) }
            ?? FetchDescriptor(sortBy: sortBy)
        let fetched = (try? syncContainer.mainContext.fetch(descriptor)) ?? []
        rows = postFetchFilter.map { fetched.filter($0) } ?? fetched
    }

    private static func defaultObservedModelTypeNames() -> Set<String> {
        var names: Set<String> = [String(reflecting: Model.self)]
        if let syncModelType = Model.self as? any SyncModelable.Type {
            names.formUnion(syncModelType.syncDefaultRefreshModelTypeNames)
        }
        return names
    }
}
