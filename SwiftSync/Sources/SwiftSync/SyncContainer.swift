import Foundation
import SwiftData
import Core

public final class SyncContainer: NSObject, @unchecked Sendable {
    public static let didSaveChangesNotification = Notification.Name("SwiftSync.SyncContainer.didSaveChanges")
    public static let changedIdentifiersUserInfoKey = "changedIdentifiers"
    public static let changedModelTypeNamesUserInfoKey = "changedModelTypeNames"

    public let modelContainer: ModelContainer
    public let mainContext: ModelContext

    @MainActor
    public init(
        for modelTypes: any PersistentModel.Type...,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil,
        configurations: ModelConfiguration...
    ) throws {
        let schema = Schema(modelTypes)
        self.modelContainer = try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: configurations
        )
        self.mainContext = modelContainer.mainContext
        super.init()
        installDidSaveObserver()
    }

    @MainActor
    public init(_ modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.mainContext = modelContainer.mainContext
        super.init()
        installDidSaveObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func makeBackgroundContext() -> ModelContext {
        ModelContext(modelContainer)
    }

    public func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as model: Model.Type,
        missingRowPolicy: SyncMissingRowPolicy = .delete
    ) async throws {
        let context = makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            missingRowPolicy: missingRowPolicy
        )
    }

    public func sync<Model: ParentScopedModel>(
        payload: [Any],
        as model: Model.Type,
        parent: Model.SyncParent,
        missingRowPolicy: SyncMissingRowPolicy = .delete
    ) async throws {
        let context = makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            parent: parent,
            missingRowPolicy: missingRowPolicy
        )
    }

    private func installDidSaveObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelContextDidSave(_:)),
            name: ModelContext.didSave,
            object: nil
        )
    }

    @objc
    private func modelContextDidSave(_ notification: Notification) {
        guard let sourceContext = notification.object as? ModelContext else { return }
        guard sourceContext.container == modelContainer else { return }
        guard sourceContext != mainContext else { return }

        let changedIDs = changedIdentifiers(from: notification.userInfo)
        for identifier in changedIDs {
            _ = mainContext.model(for: identifier)
        }
        let changedModelTypeNames = changedModelTypeNames(for: changedIDs)
        mainContext.processPendingChanges()
        NotificationCenter.default.post(
            name: Self.didSaveChangesNotification,
            object: self,
            userInfo: [
                Self.changedIdentifiersUserInfoKey: changedIDs,
                Self.changedModelTypeNamesUserInfoKey: changedModelTypeNames
            ]
        )
    }

    private func changedIdentifiers(from userInfo: [AnyHashable: Any]?) -> Set<PersistentIdentifier> {
        guard let userInfo else { return [] }

        let keys: [String] = [
            ModelContext.NotificationKey.insertedIdentifiers.rawValue,
            ModelContext.NotificationKey.updatedIdentifiers.rawValue,
            ModelContext.NotificationKey.deletedIdentifiers.rawValue
        ]

        var ids: Set<PersistentIdentifier> = []
        for key in keys {
            guard let value = userInfo[key] else { continue }
            if let setValue = value as? Set<PersistentIdentifier> {
                ids.formUnion(setValue)
                continue
            }
            if let arrayValue = value as? [PersistentIdentifier] {
                ids.formUnion(arrayValue)
            }
        }
        return ids
    }

    private func changedModelTypeNames(for identifiers: Set<PersistentIdentifier>) -> Set<String> {
        var names: Set<String> = []
        for identifier in identifiers {
            let model = mainContext.model(for: identifier)
            names.insert(String(reflecting: type(of: model)))
        }
        return names
    }
}
