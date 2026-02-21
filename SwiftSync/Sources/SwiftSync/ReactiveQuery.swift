import Combine
import Core
import Foundation
import SwiftData
import SwiftUI

private final class SyncQueryObserver<Model: PersistentModel>: ObservableObject {
    @Published var rows: [Model] = []

    private let syncContainer: SyncContainer
    private let predicate: Predicate<Model>?
    private let sortBy: [SortDescriptor<Model>]
    private let animation: Animation?
    private var notificationToken: NSObjectProtocol?

    init(
        syncContainer: SyncContainer,
        predicate: Predicate<Model>?,
        sortBy: [SortDescriptor<Model>],
        animation: Animation?
    ) {
        self.syncContainer = syncContainer
        self.predicate = predicate
        self.sortBy = sortBy
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
        ) { [weak self] _ in
            self?.reload()
        }
    }

    private func reload() {
        do {
            let descriptor: FetchDescriptor<Model>
            if let predicate {
                descriptor = FetchDescriptor(predicate: predicate, sortBy: sortBy)
            } else {
                descriptor = FetchDescriptor(sortBy: sortBy)
            }
            let resolved = try syncContainer.mainContext.fetch(descriptor)
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
        _observer = StateObject(
            wrappedValue: SyncQueryObserver(
                syncContainer: syncContainer,
                predicate: nil,
                sortBy: sortBy,
                animation: animation
            )
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
        _observer = StateObject(
            wrappedValue: SyncQueryObserver(
                syncContainer: syncContainer,
                predicate: predicate,
                sortBy: sortBy,
                animation: animation
            )
        )
    }
}

private final class SyncModelObserver<Model: PersistentModel & SyncModelable>: ObservableObject {
    @Published var model: Model?

    private let syncContainer: SyncContainer
    private let id: Model.SyncID
    private let animation: Animation?
    private var notificationToken: NSObjectProtocol?

    init(syncContainer: SyncContainer, id: Model.SyncID, animation: Animation?) {
        self.syncContainer = syncContainer
        self.id = id
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
        ) { [weak self] _ in
            self?.reload()
        }
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
            wrappedValue: SyncModelObserver(syncContainer: syncContainer, id: id, animation: animation)
        )
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
