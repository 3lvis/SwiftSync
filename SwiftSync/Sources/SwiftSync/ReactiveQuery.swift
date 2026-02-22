import Combine
import Core
import Foundation
import SwiftData
import SwiftUI

private final class SyncQueryObserver<Model: PersistentModel>: ObservableObject, @unchecked Sendable {
    @Published var rows: [Model] = []

    private let syncContainer: SyncContainer
    private let predicate: Predicate<Model>?
    private let sortBy: [SortDescriptor<Model>]
    private let postFetchFilter: ((Model) -> Bool)?
    private let observedModelTypeNames: Set<String>
    private let animation: Animation?
    private var notificationToken: NSObjectProtocol?

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
            guard let self, self.shouldReload(for: notification) else { return }
            self.reload()
        }
    }

    private func shouldReload(for notification: Notification) -> Bool {
        let changedModelTypeNames = changedModelTypeNames(from: notification.userInfo)
        if changedModelTypeNames.isEmpty {
            return true
        }

        if !observedModelTypeNames.isDisjoint(with: changedModelTypeNames) {
            return true
        }

        let changedIDs = changedIdentifiers(from: notification.userInfo)
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

private func changedIdentifiers(from userInfo: [AnyHashable: Any]?) -> Set<PersistentIdentifier> {
    guard let raw = userInfo?[SyncContainer.changedIdentifiersUserInfoKey] else { return [] }
    if let setValue = raw as? Set<PersistentIdentifier> {
        return setValue
    }
    if let arrayValue = raw as? [PersistentIdentifier] {
        return Set(arrayValue)
    }
    return []
}

private func changedModelTypeNames(from userInfo: [AnyHashable: Any]?) -> Set<String> {
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
    @StateObject private var observer: SyncQueryObserver<Model>

    public var wrappedValue: [Model] { observer.rows }

    public init(
        _ model: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
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
        _ model: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
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
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.inferredRelatedIDFilter(relatedTo: related, relatedID: relatedID),
            observedModelTypeNames: Self.defaultObservedModelTypeNames(),
            animation: animation
        )
    }

    public init<Related: SyncModelable>(
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, Related?>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToOneRelatedIDFilter(relatedTo: related, relatedID: relatedID, relationship: relationship),
            observedModelTypeNames: Self.defaultObservedModelTypeNames(),
            animation: animation
        )
    }

    public init<Related: SyncModelable>(
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, [Related]>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToManyRelatedIDFilter(relatedTo: related, relatedID: relatedID, relationship: relationship),
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
        _observer = StateObject(
            wrappedValue: SyncQueryObserver(
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

    private static func inferredRelatedIDFilter<Related: SyncModelable>(
        relatedTo related: Related.Type,
        relatedID: Related.SyncID
    ) -> (Model) -> Bool {
        _ = related

        let inferredToOne = Result { try SwiftSync.inferToOneRelationship(for: Model.self, parent: Related.self) }
        let inferredToMany = Result { try SwiftSync.inferToManyRelationship(for: Model.self, related: Related.self) }

        switch (inferredToOne, inferredToMany) {
        case (.success(let relationship), .failure):
            return explicitToOneRelatedIDFilter(relatedTo: Related.self, relatedID: relatedID, relationship: relationship)
        case (.failure, .success(let relationship)):
            return explicitToManyRelatedIDFilter(relatedTo: Related.self, relatedID: relatedID, relationship: relationship)
        case (.success, .success):
            preconditionFailure(
                "SyncQuery relatedTo inference failed for \(Model.self) -> \(Related.self): found both to-one and to-many relationships. Pass an explicit query relationship via `through:`."
            )
        case (.failure(let toOneError), .failure(let toManyError)):
            preconditionFailure(
                "SyncQuery relatedTo inference failed for \(Model.self) -> \(Related.self). Pass an explicit query relationship via `through:`. To-one error: \(toOneError). To-many error: \(toManyError)"
            )
        }
    }

    private static func explicitToOneRelatedIDFilter<Related: SyncModelable>(
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        relationship: ReferenceWritableKeyPath<Model, Related?>
    ) -> (Model) -> Bool {
        _ = related
        return { row in
            guard let relatedRow = row[keyPath: relationship] else { return false }
            return relatedRow[keyPath: Related.syncIdentity] == relatedID
        }
    }

    private static func explicitToManyRelatedIDFilter<Related: SyncModelable>(
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        relationship: ReferenceWritableKeyPath<Model, [Related]>
    ) -> (Model) -> Bool {
        _ = related
        return { row in
            row[keyPath: relationship].contains { relatedRow in
                relatedRow[keyPath: Related.syncIdentity] == relatedID
            }
        }
    }

}

public extension SyncQuery where Model: SyncModelable {
    init(
        _ model: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
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
        _ model: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
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
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.inferredRelatedIDFilter(relatedTo: related, relatedID: relatedID),
            observedModelTypeNames: Self.observedModelTypeNames(refreshOn: refreshOn),
            animation: animation
        )
    }

    init<Related: SyncModelable>(
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, Related?>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToOneRelatedIDFilter(relatedTo: related, relatedID: relatedID, relationship: relationship),
            observedModelTypeNames: Self.observedModelTypeNames(refreshOn: refreshOn),
            animation: animation
        )
    }

    init<Related: SyncModelable>(
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, [Related]>,
        in syncContainer: SyncContainer,
        sortBy: [SortDescriptor<Model>] = [],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        _ = model
        self.init(
            syncContainer: syncContainer,
            predicate: nil,
            sortBy: sortBy,
            postFetchFilter: Self.explicitToManyRelatedIDFilter(relatedTo: related, relatedID: relatedID, relationship: relationship),
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

public extension SyncQuery where Model: SyncQuerySortableModel {
    init(
        _ model: Model.Type,
        in syncContainer: SyncContainer,
        sortBy: [PartialKeyPath<Model>],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            model,
            in: syncContainer,
            sortBy: Model.syncSortDescriptors(for: sortBy),
            refreshOn: refreshOn,
            animation: animation
        )
    }

    init(
        _ model: Model.Type,
        predicate: Predicate<Model>,
        in syncContainer: SyncContainer,
        sortBy: [PartialKeyPath<Model>],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            model,
            predicate: predicate,
            in: syncContainer,
            sortBy: Model.syncSortDescriptors(for: sortBy),
            refreshOn: refreshOn,
            animation: animation
        )
    }

    init<Related: SyncModelable>(
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        in syncContainer: SyncContainer,
        sortBy: [PartialKeyPath<Model>],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            model,
            relatedTo: related,
            relatedID: relatedID,
            in: syncContainer,
            sortBy: Model.syncSortDescriptors(for: sortBy),
            refreshOn: refreshOn,
            animation: animation
        )
    }

    init<Related: SyncModelable>(
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, Related?>,
        in syncContainer: SyncContainer,
        sortBy: [PartialKeyPath<Model>],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            model,
            relatedTo: related,
            relatedID: relatedID,
            through: relationship,
            in: syncContainer,
            sortBy: Model.syncSortDescriptors(for: sortBy),
            refreshOn: refreshOn,
            animation: animation
        )
    }

    init<Related: SyncModelable>(
        _ model: Model.Type,
        relatedTo related: Related.Type,
        relatedID: Related.SyncID,
        through relationship: ReferenceWritableKeyPath<Model, [Related]>,
        in syncContainer: SyncContainer,
        sortBy: [PartialKeyPath<Model>],
        refreshOn: [PartialKeyPath<Model>] = [],
        animation: Animation? = nil
    ) {
        self.init(
            model,
            relatedTo: related,
            relatedID: relatedID,
            through: relationship,
            in: syncContainer,
            sortBy: Model.syncSortDescriptors(for: sortBy),
            refreshOn: refreshOn,
            animation: animation
        )
    }

}

private final class SyncModelObserver<Model: PersistentModel & SyncModelable>: ObservableObject, @unchecked Sendable {
    @Published var model: Model?

    private let syncContainer: SyncContainer
    private let id: Model.SyncID
    private let observedModelTypeNames: Set<String>
    private let animation: Animation?
    private var notificationToken: NSObjectProtocol?

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
            guard let self, self.shouldReload(for: notification) else { return }
            self.reload()
        }
    }

    private func shouldReload(for notification: Notification) -> Bool {
        let changedTypeNames = changedModelTypeNames(from: notification.userInfo)
        if changedTypeNames.isEmpty {
            return true
        }
        if !observedModelTypeNames.isDisjoint(with: changedTypeNames) {
            return true
        }

        guard let loadedModel = model else { return false }
        let changedIDs = changedIdentifiers(from: notification.userInfo)
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
    @StateObject private var observer: SyncModelObserver<Model>

    public var wrappedValue: Model? { observer.model }

    public init(
        _ model: Model.Type,
        id: Model.SyncID,
        in syncContainer: SyncContainer,
        animation: Animation? = nil
    ) {
        _ = model
        _observer = StateObject(
            wrappedValue: SyncModelObserver(
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

@MainActor
@propertyWrapper
@available(*, deprecated, renamed: "SyncModel")
public struct SyncModelValue<Model: PersistentModel & SyncModelable>: DynamicProperty {
    @SyncModel private var model: Model?

    public var wrappedValue: Model? { model }

    public init(
        _ modelType: Model.Type,
        id: Model.SyncID,
        in syncContainer: SyncContainer,
        animation: Animation? = nil
    ) {
        _model = SyncModel(modelType, id: id, in: syncContainer, animation: animation)
    }
}
