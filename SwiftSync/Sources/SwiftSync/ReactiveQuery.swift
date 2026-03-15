import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
private final class SyncQueryObserver<Model: PersistentModel> {
    var rows: [Model] = []

    @ObservationIgnored private let syncContainer: SyncContainer
    @ObservationIgnored private let predicate: Predicate<Model>?
    @ObservationIgnored private let sortBy: [SortDescriptor<Model>]
    @ObservationIgnored private let postFetchFilter: ((Model) -> Bool)?
    @ObservationIgnored private let observedModelTypeNames: Set<String>
    @ObservationIgnored private let animation: Animation?
    @ObservationIgnored nonisolated(unsafe) private var notificationToken: NSObjectProtocol?

    init(
        syncContainer: SyncContainer,
        predicate: Predicate<Model>?,
        sortBy: [SortDescriptor<Model>],
        postFetchFilter: ((Model) -> Bool)?,
        observedModelTypeNames: Set<String>,
        animation: Animation?
    ) {
        self.syncContainer = syncContainer
        self.predicate = predicate
        self.sortBy = sortBy
        self.postFetchFilter = postFetchFilter
        self.observedModelTypeNames = observedModelTypeNames
        self.animation = animation
        installObserver()
        reload()
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    private func installObserver() {
        notificationToken = NotificationCenter.default.addObserver(
            forName: SyncContainer.didSaveChangesNotification,
            object: syncContainer,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let changedModelTypeNames = syncQueryChangedModelTypeNames(from: notification.userInfo)
            let changedIDs = syncQueryChangedIdentifiers(from: notification.userInfo)
            MainActor.assumeIsolated {
                guard self.shouldReload(changedModelTypeNames: changedModelTypeNames, changedIDs: changedIDs) else { return }
                self.reload()
            }
        }
    }

    private func shouldReload(
        changedModelTypeNames: Set<String>,
        changedIDs: Set<PersistentIdentifier>
    ) -> Bool {
        if changedModelTypeNames.isEmpty {
            return true
        }

        if !observedModelTypeNames.isDisjoint(with: changedModelTypeNames) {
            return true
        }

        if changedIDs.isEmpty {
            return false
        }
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
            if let animation {
                withAnimation(animation) {
                    rows = resolved
                }
            } else {
                rows = resolved
            }
        } catch {
            rows = []
        }
    }
}

func syncQueryChangedIdentifiers(from userInfo: [AnyHashable: Any]?) -> Set<PersistentIdentifier> {
    guard let raw = userInfo?[SyncContainer.changedIdentifiersUserInfoKey] else { return [] }
    if let setValue = raw as? Set<PersistentIdentifier> {
        return setValue
    }
    if let arrayValue = raw as? [PersistentIdentifier] {
        return Set(arrayValue)
    }
    return []
}

func syncQueryChangedModelTypeNames(from userInfo: [AnyHashable: Any]?) -> Set<String> {
    guard let raw = userInfo?[SyncContainer.changedModelTypeNamesUserInfoKey] else { return [] }
    if let setValue = raw as? Set<String> {
        return setValue
    }
    if let arrayValue = raw as? [String] {
        return Set(arrayValue)
    }
    return []
}

@MainActor
@propertyWrapper
public struct SyncQuery<Model: PersistentModel>: DynamicProperty {
    @State private var observer: SyncQueryObserver<Model>

    public var wrappedValue: [Model] { observer.rows }

    public init(
        _ _: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: nil,
            observedModelTypeNames: Self.defaultObservedModelTypeNames(),
            animation: animation
        )
    }

    public init(
        _ _: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: predicate,
            sortBy: sortBy,
            postFetchFilter: nil,
            observedModelTypeNames: Self.defaultObservedModelTypeNames(),
            animation: animation
        )
    }

    public init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, Related?>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToOneRelationshipIDFilter(relationshipID: relationshipID, relationship: relationship),
            observedModelTypeNames: Self.defaultObservedModelTypeNames(),
            animation: animation
        )
    }

    public init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, [Related]>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToManyRelationshipIDFilter(relationshipID: relationshipID, relationship: relationship),
            observedModelTypeNames: Self.defaultObservedModelTypeNames(),
            animation: animation
        )
    }

    private init(
        syncContainer: SyncContainer,
        predicate: Predicate<Model>?,
        sortBy: [SortDescriptor<Model>],
        postFetchFilter: ((Model) -> Bool)?,
        observedModelTypeNames: Set<String>,
        animation: Animation?
    ) {
        _observer = State(
            initialValue: SyncQueryObserver(
                syncContainer: syncContainer,
                predicate: predicate,
                sortBy: sortBy,
                postFetchFilter: postFetchFilter,
                observedModelTypeNames: observedModelTypeNames,
                animation: animation
            )
        )
    }

    private static func defaultObservedModelTypeNames() -> Set<String> {
        var names: Set<String> = [String(reflecting: Model.self)]
        if let syncModelType = Model.self as? any SyncModelable.Type {
            names.formUnion(syncModelType.syncDefaultRefreshModelTypeNames)
        }
        return names
    }

    private static func explicitToOneRelationshipIDFilter<Related: SyncModelable>(
        relationshipID: Related.SyncID,
        relationship: ReferenceWritableKeyPath<Model, Related?>
    ) -> (Model) -> Bool {
        return { row in
            guard let relatedRow = row[keyPath: relationship] else { return false }
            return relatedRow[keyPath: Related.syncIdentity] == relationshipID
        }
    }

    private static func explicitToManyRelationshipIDFilter<Related: SyncModelable>(
        relationshipID: Related.SyncID,
        relationship: ReferenceWritableKeyPath<Model, [Related]>
    ) -> (Model) -> Bool {
        return { row in
            row[keyPath: relationship].contains { relatedRow in
                relatedRow[keyPath: Related.syncIdentity] == relationshipID
            }
        }
    }

}

public extension SyncQuery where Model: SyncModelable {
    init(
        _ _: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: nil,
            observedModelTypeNames: Self.observedModelTypeNames(refreshOn: refreshOn),
            animation: animation
        )
    }

    init(
        _ _: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: predicate,
            sortBy: sortBy,
            postFetchFilter: nil,
            observedModelTypeNames: Self.observedModelTypeNames(refreshOn: refreshOn),
            animation: animation
        )
    }

    init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, Related?>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToOneRelationshipIDFilter(relationshipID: relationshipID, relationship: relationship),
            observedModelTypeNames: Self.observedModelTypeNames(refreshOn: refreshOn),
            animation: animation
        )
    }

    init<Related: SyncModelable>(
        _ _: Model.Type,
        relationship: ReferenceWritableKeyPath<Model, [Related]>,
        relationshipID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToManyRelationshipIDFilter(relationshipID: relationshipID, relationship: relationship),
            observedModelTypeNames: Self.observedModelTypeNames(refreshOn: refreshOn),
            animation: animation
        )
    }

    private static func observedModelTypeNames(refreshOn: [PartialKeyPath<Model>]) -> Set<String> {
        var names = Self.defaultObservedModelTypeNames()
        names.formUnion(Model.syncRefreshModelTypeNames(for: refreshOn))
        return names
    }
}



@MainActor
@Observable
private final class SyncModelObserver<Model: PersistentModel & SyncModelable> {
    var model: Model?

    @ObservationIgnored private let syncContainer: SyncContainer
    @ObservationIgnored private let id: Model.SyncID
    @ObservationIgnored private let observedModelTypeNames: Set<String>
    @ObservationIgnored private let animation: Animation?
    @ObservationIgnored nonisolated(unsafe) private var notificationToken: NSObjectProtocol?

    init(
        syncContainer: SyncContainer,
        id: Model.SyncID,
        observedModelTypeNames: Set<String>,
        animation: Animation?
    ) {
        self.syncContainer = syncContainer
        self.id = id
        self.observedModelTypeNames = observedModelTypeNames
        self.animation = animation
        installObserver()
        reload()
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    private func installObserver() {
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

        guard let loadedModel = model else { return false }
        return changedIDs.contains(loadedModel.persistentModelID)
    }

    private func reload() {
        do {
            let rows = try syncContainer.mainContext.fetch(FetchDescriptor<Model>())
            let matched = rows.first { $0[keyPath: Model.syncIdentity] == id }
            if let animation {
                withAnimation(animation) {
                    model = matched
                }
            } else {
                model = matched
            }
        } catch {
            model = nil
        }
    }
}

@MainActor
@propertyWrapper
public struct SyncModel<Model: PersistentModel & SyncModelable>: DynamicProperty {
    @State private var observer: SyncModelObserver<Model>

    public var wrappedValue: Model? { observer.model }

    public init(
        _ _: Model.Type,
        id: Model.SyncID,
        in syncContainer: SyncContainer,
        animation: Animation? = nil
    ) {
        _observer = State(
            initialValue: SyncModelObserver(
                syncContainer: syncContainer,
                id: id,
                observedModelTypeNames: Self.defaultObservedModelTypeNames(),
                animation: animation
            )
        )
    }

    private static func defaultObservedModelTypeNames() -> Set<String> {
        var names = Model.syncDefaultRefreshModelTypeNames
        names.insert(String(reflecting: Model.self))
        return names
    }
}
