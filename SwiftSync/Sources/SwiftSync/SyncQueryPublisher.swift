import Combine
import Core
import Foundation
import SwiftData

// @unchecked Sendable matches the pattern used by the private observers in ReactiveQuery.swift;
// the notification closure is dispatched on queue: .main so mutation is always on the main thread.
public final class SyncQueryPublisher<Model: PersistentModel>: ObservableObject, @unchecked Sendable {

    // MARK: - Public interface

    @Published public private(set) var rows: [Model] = []
    public var rowsPublisher: AnyPublisher<[Model], Never> { $rows.eraseToAnyPublisher() }

    // MARK: - Private state

    private let syncContainer: SyncContainer
    private let predicate: Predicate<Model>?
    private let sortBy: [SortDescriptor<Model>]
    private let postFetchFilter: ((Model) -> Bool)?
    private let observedModelTypeNames: Set<String>
    private var notificationToken: NSObjectProtocol?

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
            guard let self, self.shouldReload(for: notification.userInfo) else { return }
            self.reload()
        }
        reload()
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
        relatedTo _: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, Related?>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: { row in
                guard let related = row[keyPath: relationship] else { return false }
                return related[keyPath: Related.syncIdentity] == relatedID
            }
        )
    }

    public convenience init<Related: SyncModelable>(
        _ _: Model.Type,
        relatedTo _: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, [Related]>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: { row in
                row[keyPath: relationship].contains { $0[keyPath: Related.syncIdentity] == relatedID }
            }
        )
    }

    // MARK: - Teardown

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    // MARK: - Private

    private func shouldReload(for userInfo: [AnyHashable: Any]?) -> Bool {
        let changedTypeNames = syncQueryChangedModelTypeNames(from: userInfo)
        if changedTypeNames.isEmpty { return true }
        if !observedModelTypeNames.isDisjoint(with: changedTypeNames) { return true }

        let changedIDs = syncQueryChangedIdentifiers(from: userInfo)
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
