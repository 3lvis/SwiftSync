import Combine
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
    private let sortBy: [SortDescriptor<Model>]
    private let observedModelTypeNames: Set<String>
    private var notificationToken: NSObjectProtocol?

    // MARK: - Public init

    public init(
        _ _: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.syncContainer = syncContainer
        self.sortBy = sortBy
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
        let descriptor = FetchDescriptor<Model>(sortBy: sortBy)
        rows = (try? syncContainer.mainContext.fetch(descriptor)) ?? []
    }

    private static func defaultObservedModelTypeNames() -> Set<String> {
        var names: Set<String> = [String(reflecting: Model.self)]
        if let syncModelType = Model.self as? any SyncModelable.Type {
            names.formUnion(syncModelType.syncDefaultRefreshModelTypeNames)
        }
        return names
    }
}
