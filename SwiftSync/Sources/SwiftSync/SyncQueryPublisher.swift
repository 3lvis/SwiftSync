import Combine
import Core
import Foundation
import SwiftData

/// A Combine-backed observable that tracks a SwiftData query and republishes
/// the result set whenever relevant changes are saved through a `SyncContainer`.
///
/// This is the UIKit (and plain-Swift) counterpart to `@SyncQuery`. Because it
/// does not depend on SwiftUI, it can be used from any context — `UIViewController`,
/// `UITableViewDiffableDataSource`, or a plain coordinator object.
///
/// ### Basic usage
/// ```swift
/// // Hold a strong reference (e.g. as a property on your view controller).
/// let taskPublisher = SyncQueryPublisher(
///     Task.self,
///     in: syncContainer,
///     sortBy: [SortDescriptor(\Task.title)]
/// )
///
/// // Subscribe in viewDidLoad / viewWillAppear.
/// taskPublisher.rowsPublisher
///     .receive(on: DispatchQueue.main)
///     .sink { [weak self] tasks in
///         self?.applySnapshot(tasks)
///     }
///     .store(in: &cancellables)
/// ```
///
/// ### Filtered by a related model (UIKit "User Tasks" pattern)
/// ```swift
/// let publisher = SyncQueryPublisher(
///     Task.self,
///     relatedTo: User.self,
///     relatedID: userID,
///     through: \Task.assignee,
///     in: syncContainer,
///     sortBy: [SortDescriptor(\Task.title)]
/// )
/// ```
public final class SyncQueryPublisher<Model: PersistentModel>: ObservableObject, @unchecked Sendable {

    // MARK: - Public interface

    /// The current result set. Always updated on the main thread.
    @Published public private(set) var rows: [Model] = []

    /// A type-erased publisher that emits the new `rows` array whenever it changes.
    public var rowsPublisher: AnyPublisher<[Model], Never> { $rows.eraseToAnyPublisher() }

    // MARK: - Private state

    private let syncContainer: SyncContainer
    private let predicate: Predicate<Model>?
    private let sortBy: [SortDescriptor<Model>]
    private let postFetchFilter: ((Model) -> Bool)?
    private let observedModelTypeNames: Set<String>
    private var notificationToken: NSObjectProtocol?

    // MARK: - Init (plain fetch)

    /// Observes all rows of `Model`, sorted by `sortBy`.
    public init(
        _ _: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.syncContainer = syncContainer
        self.predicate = nil
        self.sortBy = sortBy
        self.postFetchFilter = nil
        self.observedModelTypeNames = Self.defaultObservedModelTypeNames()
        setup()
    }

    /// Observes rows of `Model` matching `predicate`, sorted by `sortBy`.
    public init(
        _ _: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.syncContainer = syncContainer
        self.predicate = predicate
        self.sortBy = sortBy
        self.postFetchFilter = nil
        self.observedModelTypeNames = Self.defaultObservedModelTypeNames()
        setup()
    }

    // MARK: - Init (relatedTo — explicit to-one)

    /// Observes rows of `Model` whose `relationship` points to the given `relatedID`.
    public init<Related: SyncModelable>(
        _ _: Model.Type,
        relatedTo _: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, Related?>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.syncContainer = syncContainer
        self.predicate = nil
        self.sortBy = sortBy
        self.postFetchFilter = Self.toOneFilter(relatedID: relatedID, through: relationship)
        self.observedModelTypeNames = Self.defaultObservedModelTypeNames()
        setup()
    }

    // MARK: - Init (relatedTo — explicit to-many)

    /// Observes rows of `Model` that appear in the `relationship` collection for the given `relatedID`.
    public init<Related: SyncModelable>(
        _ _: Model.Type,
        relatedTo _: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, [Related]>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = []
    ) {
        self.syncContainer = syncContainer
        self.predicate = nil
        self.sortBy = sortBy
        self.postFetchFilter = Self.toManyFilter(relatedID: relatedID, through: relationship)
        self.observedModelTypeNames = Self.defaultObservedModelTypeNames()
        setup()
    }

    // MARK: - Teardown

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    // MARK: - Private helpers

    private func setup() {
        installObserver()
        reload()
    }

    private func installObserver() {
        notificationToken = NotificationCenter.default.addObserver(
            forName: SyncContainer.didSaveChangesNotification,
            object: syncContainer,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.shouldReload(for: notification.userInfo) else { return }
            self.reload()
        }
    }

    private func shouldReload(for userInfo: [AnyHashable: Any]?) -> Bool {
        let changedTypeNames = syncQueryChangedModelTypeNames(from: userInfo)
        if changedTypeNames.isEmpty { return true }
        if !observedModelTypeNames.isDisjoint(with: changedTypeNames) { return true }

        let changedIDs = syncQueryChangedIdentifiers(from: userInfo)
        if changedIDs.isEmpty { return false }
        let loadedIDs = Set(rows.map(\.persistentModelID))
        return !loadedIDs.isDisjoint(with: changedIDs)
    }

    private func reload() {
        do {
            let descriptor: FetchDescriptor<Model>
            if let predicate {
                descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
            } else {
                descriptor = FetchDescriptor(sortBy: sortBy)
            }
            var resolved = try syncContainer.mainContext.fetch(descriptor)
            if let postFetchFilter {
                resolved = resolved.filter(postFetchFilter)
            }
            rows = resolved
        } catch {
            rows = []
        }
    }

    // MARK: - Static filter builders

    private static func defaultObservedModelTypeNames() -> Set<String> {
        var names: Set<String> = [String(reflecting: Model.self)]
        if let syncModelType = Model.self as? any SyncModelable.Type {
            names.formUnion(syncModelType.syncDefaultRefreshModelTypeNames)
        }
        return names
    }

    private static func toOneFilter<Related: SyncModelable>(
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, Related?>
    ) -> (Model) -> Bool {
        return { row in
            guard let related = row[keyPath: relationship] else { return false }
            return related[keyPath: Related.syncIdentity] == relatedID
        }
    }

    private static func toManyFilter<Related: SyncModelable>(
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, [Related]>
    ) -> (Model) -> Bool {
        return { row in
            row[keyPath: relationship].contains { $0[keyPath: Related.syncIdentity] == relatedID }
        }
    }
}
