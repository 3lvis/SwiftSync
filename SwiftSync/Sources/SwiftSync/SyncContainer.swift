import Foundation
import SwiftData
import Core
import ObjCExceptionCatcher

public final class SyncContainer: NSObject, @unchecked Sendable {
    public struct ObjectiveCInitializationExceptionError: LocalizedError, Sendable {
        public let name: String?
        public let reason: String?

        public var errorDescription: String? {
            if let reason, !reason.isEmpty { return reason }
            if let name, !name.isEmpty { return name }
            return "Objective-C exception during ModelContainer initialization."
        }
    }

    public enum InitializationFailureRecovery: Sendable {
        case none
        case resetAndRetry
    }

    public static let didSaveChangesNotification = Notification.Name("SwiftSync.SyncContainer.didSaveChanges")
    public static let changedIdentifiersUserInfoKey = "changedIdentifiers"
    public static let changedModelTypeNamesUserInfoKey = "changedModelTypeNames"

    public let modelContainer: ModelContainer
    public let mainContext: ModelContext
    public let inputKeyStyle: SyncInputKeyStyle

    @MainActor
    public init(
        for modelTypes: any PersistentModel.Type...,
        inputKeyStyle: SyncInputKeyStyle = .snakeCase,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil,
        initializationFailureRecovery: InitializationFailureRecovery = .none,
        configurations: ModelConfiguration...
    ) throws {
        let schema = Schema(modelTypes)
        self.modelContainer = try Self._recoverContainerInitialization(
            recovery: initializationFailureRecovery,
            configurations: configurations,
            makeContainer: {
                try Self._executeCatchingObjectiveCException {
                    try ModelContainer(
                        for: schema,
                        migrationPlan: migrationPlan,
                        configurations: configurations
                    )
                }
            },
            resetPersistentStores: Self._resetPersistentStoreFiles(for:)
        )
        self.mainContext = modelContainer.mainContext
        self.inputKeyStyle = inputKeyStyle
        super.init()
        installDidSaveObserver()
    }

    @MainActor
    public init(_ modelContainer: ModelContainer, inputKeyStyle: SyncInputKeyStyle = .snakeCase) {
        self.modelContainer = modelContainer
        self.mainContext = modelContainer.mainContext
        self.inputKeyStyle = inputKeyStyle
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
        missingRowPolicy: SyncMissingRowPolicy = .delete,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let context = makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            inputKeyStyle: inputKeyStyle,
            missingRowPolicy: missingRowPolicy,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: ParentScopedModel>(
        payload: [Any],
        as model: Model.Type,
        parent: Model.SyncParent,
        missingRowPolicy: SyncMissingRowPolicy = .delete,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let context = makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            parent: parent,
            inputKeyStyle: inputKeyStyle,
            missingRowPolicy: missingRowPolicy,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        payload: [Any],
        as model: Model.Type,
        parent: Parent,
        identityPolicy: SyncIdentityPolicy = .global,
        missingRowPolicy: SyncMissingRowPolicy = .delete,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let context = makeBackgroundContext()
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            parent: parent,
            identityPolicy: identityPolicy,
            inputKeyStyle: inputKeyStyle,
            missingRowPolicy: missingRowPolicy,
            relationshipOperations: relationshipOperations
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

    static func _recoverContainerInitialization<T>(
        recovery: InitializationFailureRecovery,
        configurations: [ModelConfiguration],
        makeContainer: () throws -> T,
        resetPersistentStores: ([ModelConfiguration]) throws -> Void
    ) throws -> T {
        do {
            return try makeContainer()
        } catch {
            guard recovery == .resetAndRetry else {
                throw error
            }
            try resetPersistentStores(configurations)
            return try makeContainer()
        }
    }

    static func _executeCatchingObjectiveCException<T>(_ body: () throws -> T) throws -> T {
        var swiftResult: Result<T, Error>?
        do {
            try SwiftSyncObjCExceptionCatcher.`try`({
                do {
                    swiftResult = .success(try body())
                } catch {
                    swiftResult = .failure(error)
                }
            })
        } catch {
            let nsError = error as NSError
            let userInfo = nsError.userInfo
            let name = userInfo[SwiftSyncObjCExceptionNameKey] as? String
            let reason = userInfo[SwiftSyncObjCExceptionReasonKey] as? String ?? nsError.localizedDescription
            throw ObjectiveCInitializationExceptionError(name: name, reason: reason)
        }

        if let swiftResult {
            return try swiftResult.get()
        }

        fatalError("SwiftSyncObjCExceptionCatcher returned no result and no error.")
    }

    static func _resetPersistentStoreFiles(for configurations: [ModelConfiguration]) throws {
        let fm = FileManager.default

        for configuration in configurations {
            let storeURL = configuration.url

            let directory = storeURL.deletingLastPathComponent()
            let baseName = storeURL.lastPathComponent
            guard fm.fileExists(atPath: directory.path) else { continue }

            let children = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            )

            for child in children {
                let name = child.lastPathComponent
                guard name == baseName || name.hasPrefix(baseName) else { continue }
                try fm.removeItem(at: child)
            }
        }
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
