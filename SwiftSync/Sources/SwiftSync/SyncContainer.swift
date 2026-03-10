import Foundation
import SwiftData
import ObjCExceptionCatcher

public final class SyncContainer: NSObject, @unchecked Sendable {
    public struct SchemaValidationError: LocalizedError, Sendable {
        public let message: String

        public var errorDescription: String? { message }

        public init(message: String) {
            self.message = message
        }
    }

    public struct ObjectiveCInitializationExceptionError: LocalizedError, Sendable {
        public let name: String?
        public let reason: String?

        public var errorDescription: String? {
            if let reason, !reason.isEmpty { return reason }
            if let name, !name.isEmpty { return name }
            return "Objective-C exception during ModelContainer initialization."
        }
    }

    static let didSaveChangesNotification = Notification.Name("SwiftSync.SyncContainer.didSaveChanges")
    static let changedIdentifiersUserInfoKey = "changedIdentifiers"
    static let changedModelTypeNamesUserInfoKey = "changedModelTypeNames"

    public let modelContainer: ModelContainer
    public let mainContext: ModelContext
    public let keyStyle: KeyStyle
    public let dateFormatter: DateFormatter

    @MainActor
    public init(
        for modelTypes: any PersistentModel.Type...,
        keyStyle: KeyStyle = .snakeCase,
        dateFormatter: DateFormatter? = nil,
        recoverOnFailure: Bool = false,
        configurations: ModelConfiguration...
    ) throws {
        try Self._validateSchema(modelTypes: modelTypes)
        let schema = Schema(modelTypes)
        self.modelContainer = try Self._recoverContainerInitialization(
            recoverOnFailure: recoverOnFailure,
            configurations: configurations,
            makeContainer: {
                try Self._executeCatchingObjectiveCException {
                    try ModelContainer(
                        for: schema,
                        configurations: configurations
                    )
                }
            },
            resetPersistentStores: Self._resetPersistentStoreFiles(for:)
        )
        self.mainContext = modelContainer.mainContext
        self.keyStyle = keyStyle
        self.dateFormatter = dateFormatter ?? defaultExportDateFormatter()
        super.init()
        installDidSaveObserver()
    }

    @MainActor
    public init(_ modelContainer: ModelContainer, keyStyle: KeyStyle = .snakeCase, dateFormatter: DateFormatter? = nil) {
        self.modelContainer = modelContainer
        self.mainContext = modelContainer.mainContext
        self.keyStyle = keyStyle
        self.dateFormatter = dateFormatter ?? defaultExportDateFormatter()
        super.init()
        installDidSaveObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as model: Model.Type,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let context = ModelContext(modelContainer)
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            keyStyle: keyStyle,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel, Payload: SyncPayloadConvertible>(
        payload: [Payload],
        as model: Model.Type,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        try await sync(
            payload: payload.map { $0.toSyncPayloadDictionary() },
            as: model,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        payload: [Any],
        as model: Model.Type,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let context = ModelContext(modelContainer)
        try await SwiftSync.sync(
            payload: payload,
            as: model,
            in: context,
            parent: parent,
            relationship: relationship,
            keyStyle: keyStyle,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel, Payload: SyncPayloadConvertible, Parent: PersistentModel>(
        payload: [Payload],
        as model: Model.Type,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        try await sync(
            payload: payload.map { $0.toSyncPayloadDictionary() },
            as: model,
            parent: parent,
            relationship: relationship,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel>(
        item: [String: Any],
        as model: Model.Type,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let context = ModelContext(modelContainer)
        try await SwiftSync.sync(
            item: item,
            as: model,
            in: context,
            keyStyle: keyStyle,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel, Payload: SyncPayloadConvertible>(
        item: Payload,
        as model: Model.Type,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        try await sync(
            item: item.toSyncPayloadDictionary(),
            as: model,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
        item: [String: Any],
        as model: Model.Type,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        let context = ModelContext(modelContainer)
        try await SwiftSync.sync(
            item: item,
            as: model,
            in: context,
            parent: parent,
            relationship: relationship,
            keyStyle: keyStyle,
            relationshipOperations: relationshipOperations
        )
    }

    public func sync<Model: SyncUpdatableModel, Payload: SyncPayloadConvertible, Parent: PersistentModel>(
        item: Payload,
        as model: Model.Type,
        parent: Parent,
        relationship: ReferenceWritableKeyPath<Model, Parent?>,
        relationshipOperations: SyncRelationshipOperations = .all
    ) async throws {
        try await sync(
            item: item.toSyncPayloadDictionary(),
            as: model,
            parent: parent,
            relationship: relationship,
            relationshipOperations: relationshipOperations
        )
    }

    public func export<Model: SyncUpdatableModel>(as _: Model.Type) throws -> [[String: Any]] {
        let context = ModelContext(modelContainer)
        let rows = try syncProfile("export-fetch") {
            try context.fetch(FetchDescriptor<Model>())
        }
        let sorted = syncProfile("export-sort") {
            rows.sorted { lhs, rhs in
                String(describing: lhs[keyPath: Model.syncIdentity]) < String(describing: rhs[keyPath: Model.syncIdentity])
            }
        }

        return syncProfile("export-map") {
            sorted.map { row in
                row.exportObject(keyStyle: keyStyle, dateFormatter: dateFormatter)
            }
        }
    }

    public func export<Model: SyncUpdatableModel & ParentScopedModel>(
        as _: Model.Type,
        parent: Model.SyncParent
    ) throws -> [[String: Any]] {
        let context = ModelContext(modelContainer)
        let rows: [Model]
        if let predicate = Model.syncParentPredicate(
            parentPersistentID: parent.persistentModelID,
            relationship: Model.parentRelationship
        ) {
            rows = try syncProfile("export-fetch-by-parent") {
                try context.fetch(FetchDescriptor<Model>(predicate: predicate))
            }
        } else {
            let allRows = try syncProfile("export-fetch") {
                try context.fetch(FetchDescriptor<Model>())
            }
            rows = syncProfile("export-filter-scope") {
                allRows.filter { $0[keyPath: Model.parentRelationship]?.persistentModelID == parent.persistentModelID }
            }
        }
        let sorted = syncProfile("export-sort") {
            rows.sorted { lhs, rhs in
                String(describing: lhs[keyPath: Model.syncIdentity]) < String(describing: rhs[keyPath: Model.syncIdentity])
            }
        }

        return syncProfile("export-map") {
            sorted.map { row in
                row.exportObject(keyStyle: keyStyle, dateFormatter: dateFormatter)
            }
        }
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
        recoverOnFailure: Bool,
        configurations: [ModelConfiguration],
        makeContainer: () throws -> T,
        resetPersistentStores: ([ModelConfiguration]) throws -> Void
    ) throws -> T {
        do {
            return try makeContainer()
        } catch {
            guard recoverOnFailure else { throw error }
            try resetPersistentStores(configurations)
            return try makeContainer()
        }
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

    struct _SchemaRelationship: Sendable {
        let ownerTypeName: String
        let propertyName: String
        let relatedTypeName: String
        let isToMany: Bool
        let hasExplicitInverseAnchor: Bool

        var fullName: String { "\(ownerTypeName).\(propertyName)" }
    }

    static func _validateSchema(
        modelTypes: [any PersistentModel.Type]
    ) throws {

        let relationships = _schemaRelationships(from: modelTypes)
            .sorted { lhs, rhs in
                if lhs.ownerTypeName != rhs.ownerTypeName { return lhs.ownerTypeName < rhs.ownerTypeName }
                return lhs.propertyName < rhs.propertyName
            }

        for relationship in relationships where relationship.isToMany {
            let reciprocalToMany = relationships.filter {
                $0.ownerTypeName == relationship.relatedTypeName &&
                $0.relatedTypeName == relationship.ownerTypeName &&
                $0.isToMany
            }
            guard !reciprocalToMany.isEmpty else { continue } // not many-to-many

            let hasAnchor = relationship.hasExplicitInverseAnchor ||
                reciprocalToMany.contains(where: \.hasExplicitInverseAnchor)
            guard !hasAnchor else { continue }

            let reciprocalList = reciprocalToMany.map(\.fullName).joined(separator: ", ")
            throw SchemaValidationError(
                message:
                    """
                    Invalid many-to-many relationship pair with zero explicit inverse anchors. \
                    Found \(relationship.fullName) <-> [\(reciprocalList)]. \
                    Add one @Relationship(inverse: ...) anchor on either side of the many-to-many pair.
                    """
            )
        }
    }

    static func _schemaRelationships(from modelTypes: [any PersistentModel.Type]) -> [_SchemaRelationship] {
        var output: [_SchemaRelationship] = []
        for modelType in modelTypes {
            guard let syncModelType = modelType as? any SyncModelable.Type else { continue }
            let ownerTypeName = String(reflecting: modelType)
            for descriptor in syncModelType.syncRelationshipSchemaDescriptors {
                output.append(
                    _SchemaRelationship(
                        ownerTypeName: ownerTypeName,
                        propertyName: descriptor.propertyName,
                        relatedTypeName: descriptor.relatedTypeName,
                        isToMany: descriptor.isToMany,
                        hasExplicitInverseAnchor: descriptor.hasExplicitInverseAnchor
                    )
                )
            }
        }
        return output
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
