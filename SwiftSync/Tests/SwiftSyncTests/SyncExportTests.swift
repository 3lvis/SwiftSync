import XCTest
import SwiftData
@testable import SwiftSync

@Syncable
@Model
final class ExportTask {
    @Attribute(.unique) var id: Int
    var completed: Bool
    var createdAt: Date
    var nickname: String?

    init(id: Int, completed: Bool, createdAt: Date, nickname: String? = nil) {
        self.id = id
        self.completed = completed
        self.createdAt = createdAt
        self.nickname = nickname
    }
}

@Syncable
@Model
final class ExportAcronymRecord {
    @Attribute(.unique) var id: Int
    var projectID: String

    init(id: Int, projectID: String) {
        self.id = id
        self.projectID = projectID
    }
}

@Syncable
@Model
final class ExportRemotePrimary {
    @PrimaryKey(remote: "external_id")
    @Attribute(.unique) var xid: String
    var name: String

    init(xid: String, name: String) {
        self.xid = xid
        self.name = name
    }
}

@Syncable
@Model
final class ExportBarePrimary {
    @PrimaryKey
    @Attribute(.unique) var externalID: String
    var name: String

    init(externalID: String, name: String) {
        self.externalID = externalID
        self.name = name
    }
}

@Syncable
@Model
final class ExportBinaryDecimalRecord {
    @Attribute(.unique) var id: Int
    var blob: Data
    var amount: Decimal

    init(id: Int, blob: Data, amount: Decimal) {
        self.id = id
        self.blob = blob
        self.amount = amount
    }
}

private struct ExportUnsupportedScalarValue {
    let raw: Int
}

@Syncable
@Model
final class ExportMappedFields {
    @Attribute(.unique) var id: Int
    @RemoteKey("type") var userType: String
    @RemoteKey("profile.contact.email") var email: String?
    @NotExport var localOnly: String

    init(id: Int, userType: String, email: String?, localOnly: String) {
        self.id = id
        self.userType = userType
        self.email = email
        self.localOnly = localOnly
    }
}

@Syncable
@Model
final class ExportCompany {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class ExportNote {
    @Attribute(.unique) var id: Int
    var text: String
    @NotExport var user: ExportUser?

    init(id: Int, text: String, user: ExportUser? = nil) {
        self.id = id
        self.text = text
        self.user = user
    }
}

@Syncable
@Model
final class ExportUser {
    @Attribute(.unique) var id: Int
    var name: String
    var company: ExportCompany?
    @Relationship(inverse: \ExportNote.user)
    var notes: [ExportNote]

    init(id: Int, name: String, company: ExportCompany? = nil, notes: [ExportNote] = []) {
        self.id = id
        self.name = name
        self.company = company
        self.notes = notes
    }
}

@Model
final class ExportParent {
    @Attribute(.unique) var id: Int
    var name: String
    var children: [ExportChild]

    init(id: Int, name: String, children: [ExportChild] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

@Syncable
@Model
final class ExportChild {
    @Attribute(.unique) var id: Int
    var text: String
    @NotExport @Relationship(inverse: \ExportParent.children) var parent: ExportParent?

    init(id: Int, text: String, parent: ExportParent? = nil) {
        self.id = id
        self.text = text
        self.parent = parent
    }
}

extension ExportChild: ParentScopedModel {
    typealias SyncParent = ExportParent
    static var parentRelationship: ReferenceWritableKeyPath<ExportChild, ExportParent?> { \.parent }
}

@Model
final class ManualExportParent {
    @Attribute(.unique) var id: Int
    var name: String
    var children: [ManualExportChild]

    init(id: Int, name: String, children: [ManualExportChild] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

@Model
final class ManualExportChild {
    @Attribute(.unique) var id: Int
    var text: String
    @Relationship(inverse: \ManualExportParent.children) var parent: ManualExportParent?

    init(id: Int, text: String, parent: ManualExportParent? = nil) {
        self.id = id
        self.text = text
        self.parent = parent
    }
}

extension ManualExportChild: SyncUpdatableModel {
    typealias SyncID = Int

    static var syncIdentity: KeyPath<ManualExportChild, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> ManualExportChild {
        ManualExportChild(
            id: try payload.required(for: "id"),
            text: try payload.required(for: "text")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        let nextText: String = try payload.required(for: "text")
        guard text != nextText else { return false }
        text = nextText
        return true
    }

    func export(keyStyle _: KeyStyle, dateFormatter _: DateFormatter) -> [String: Any] {
        [
            "id": id,
            "text": text
        ]
    }
}

extension ManualExportChild: ParentScopedModel {
    typealias SyncParent = ManualExportParent
    static var parentRelationship: ReferenceWritableKeyPath<ManualExportChild, ManualExportParent?> { \.parent }
}

@Syncable
@Model
final class CycleNode {
    @Attribute(.unique) var id: Int
    var name: String
    var parent: CycleNode?

    init(id: Int, name: String, parent: CycleNode? = nil) {
        self.id = id
        self.name = name
        self.parent = parent
    }
}

/// A Task-like model used to test that update bodies via export
/// correctly honor @RemoteKey("description") and @RemoteKey("state.id/label"),
/// matching the gap that existed before update adopted the export pattern.
@Syncable
@Model
final class UpdateTaskLike {
    @Attribute(.unique) var id: String
    @RemoteKey("description") var descriptionText: String
    @RemoteKey("state.id") var state: String
    @RemoteKey("state.label") var stateLabel: String

    init(id: String, descriptionText: String, state: String, stateLabel: String) {
        self.id = id
        self.descriptionText = descriptionText
        self.state = state
        self.stateLabel = stateLabel
    }
}

// Compile-time regression: export must be a requirement of SyncUpdatableModel,
// not a separate ExportModel protocol. This function would not compile if export
// were missing from SyncUpdatableModel.
private func _assertExportIsOnSyncUpdatableModel<M: SyncUpdatableModel>(
    _ model: M,
    keyStyle: KeyStyle,
    dateFormatter: DateFormatter
) -> [String: Any] {
    model.export(keyStyle: keyStyle, dateFormatter: dateFormatter)
}

final class ExportTests: XCTestCase {
    @MainActor
    func testExportDefaultsSnakeCaseAndISODate() throws {
        let syncContainer = try makeSyncContainer(for: ExportTask.self)
        let context = syncContainer.mainContext
        context.insert(ExportTask(id: 9, completed: false, createdAt: Date(timeIntervalSince1970: 1_700_000_000)))
        try context.save()

        let task = try fetchSingle(ExportTask.self, from: context)
        let body = syncContainer.export(task)
        XCTAssertEqual(body["id"] as? Int, 9)
        XCTAssertEqual(body["completed"] as? Bool, false)
        XCTAssertNotNil(body["created_at"] as? String)
    }

    @MainActor
    func testExportCamelCaseKeys() throws {
        let syncContainer = try makeSyncContainer(for: ExportTask.self, keyStyle: .camelCase)
        let context = syncContainer.mainContext
        context.insert(ExportTask(id: 1, completed: true, createdAt: Date(timeIntervalSince1970: 0)))
        try context.save()

        let task = try fetchSingle(ExportTask.self, from: context)
        let body = syncContainer.export(task)
        XCTAssertNotNil(body["createdAt"])
        XCTAssertNil(body["created_at"])
    }

    @MainActor
    func testExportSnakeCaseNormalizesAcronyms() throws {
        let syncContainer = try makeSyncContainer(for: ExportAcronymRecord.self)
        let context = syncContainer.mainContext
        context.insert(ExportAcronymRecord(id: 1, projectID: "P-100"))
        try context.save()

        let record = try fetchSingle(ExportAcronymRecord.self, from: context)
        let body = syncContainer.export(record)
        XCTAssertEqual(body["project_id"] as? String, "P-100")
        XCTAssertNil(body["project_i_d"])
    }

    @MainActor
    func testExportPrimaryKeyRemoteMapping() throws {
        let syncContainer = try makeSyncContainer(for: ExportRemotePrimary.self)
        let context = syncContainer.mainContext
        context.insert(ExportRemotePrimary(xid: "abc", name: "n"))
        try context.save()

        let record = try fetchSingle(ExportRemotePrimary.self, from: context)
        let body = syncContainer.export(record)
        XCTAssertEqual(body["external_id"] as? String, "abc")
        XCTAssertNil(body["xid"])
    }

    @MainActor
    func testExportPrimaryKeyUsesDefaultKeyStyleForBarePrimaryKey() throws {
        let syncContainer = try makeSyncContainer(for: ExportBarePrimary.self)
        let context = syncContainer.mainContext
        context.insert(ExportBarePrimary(externalID: "ext-1", name: "n"))
        try context.save()

        let record = try fetchSingle(ExportBarePrimary.self, from: context)
        let body = syncContainer.export(record)
        XCTAssertEqual(body["external_id"] as? String, "ext-1")
        XCTAssertNil(body["externalID"])
    }

    @MainActor
    func testExportUnsupportedScalarFallsBackToNSNull() throws {
        var body: [String: Any] = [:]
        let raw = ExportUnsupportedScalarValue(raw: 10)
        if let encoded = exportEncodeValue(raw, dateFormatter: defaultExportDateFormatter()) {
            exportSetValue(encoded, for: "value", into: &body)
        } else {
            exportSetValue(NSNull(), for: "value", into: &body)
        }

        XCTAssertTrue(body["value"] is NSNull)
    }

    @MainActor
    func testExportEncodesDataAndDecimal() throws {
        let syncContainer = try makeSyncContainer(for: ExportBinaryDecimalRecord.self)
        let context = syncContainer.mainContext
        let blob = Data("swift-sync".utf8)
        let amount = Decimal(string: "42.75")!
        context.insert(ExportBinaryDecimalRecord(id: 11, blob: blob, amount: amount))
        try context.save()

        let record = try fetchSingle(ExportBinaryDecimalRecord.self, from: context)
        let body = syncContainer.export(record)
        XCTAssertEqual(body["blob"] as? String, blob.base64EncodedString())
        XCTAssertEqual((body["amount"] as? NSDecimalNumber)?.decimalValue, amount)
    }

    @MainActor
    func testExportNotExportAndNestedRemoteKey() throws {
        let syncContainer = try makeSyncContainer(for: ExportMappedFields.self)
        let context = syncContainer.mainContext
        context.insert(ExportMappedFields(id: 2, userType: "admin", email: "a@b.com", localOnly: "secret"))
        try context.save()

        let model = try fetchSingle(ExportMappedFields.self, from: context)
        let body = syncContainer.export(model)
        XCTAssertEqual(body["type"] as? String, "admin")
        XCTAssertNil(body["user_type"])
        XCTAssertNil(body["local_only"])

        let profile = body["profile"] as? [String: Any]
        let contact = profile?["contact"] as? [String: Any]
        XCTAssertEqual(contact?["email"] as? String, "a@b.com")
    }

    @MainActor
    func testExportRelationshipModesArray() throws {
        let syncContainer = try makeSyncContainer(for: ExportUser.self, ExportCompany.self, ExportNote.self)
        let context = syncContainer.mainContext
        let company = ExportCompany(id: 7, name: "Acme")
        let note0 = ExportNote(id: 10, text: "n0")
        let note1 = ExportNote(id: 11, text: "n1")
        context.insert(company)
        context.insert(note0)
        context.insert(note1)
        context.insert(ExportUser(id: 1, name: "U", company: company, notes: [note0, note1]))
        try context.save()

        let user = try fetchSingle(ExportUser.self, from: context)
        let body = syncContainer.export(user)
        XCTAssertEqual((body["company"] as? [String: Any])?["id"] as? Int, 7)
        XCTAssertEqual((body["notes"] as? [[String: Any]])?.count, 2)
    }

    @MainActor
    func testExportNilNestedRemoteKeyAlwaysEmitsNSNull() throws {
        let syncContainer = try makeSyncContainer(for: ExportMappedFields.self)
        let context = syncContainer.mainContext
        context.insert(ExportMappedFields(id: 3, userType: "member", email: nil, localOnly: "secret"))
        try context.save()

        let model = try fetchSingle(ExportMappedFields.self, from: context)
        let body = syncContainer.export(model)
        let profile = body["profile"] as? [String: Any]
        let contact = profile?["contact"] as? [String: Any]
        XCTAssertTrue(contact?["email"] is NSNull, "Nil optional under @RemoteKey nested path must always emit NSNull")
    }

    @MainActor
    func testExportNotExportRelationshipOmitsRelationshipKey() throws {
        let syncContainer = try makeSyncContainer(for: ExportParent.self, ExportChild.self)
        let context = syncContainer.mainContext
        let parent = ExportParent(id: 9, name: "P")
        let child = ExportChild(id: 1, text: "c1", parent: parent)
        context.insert(parent)
        context.insert(child)
        try context.save()

        let model = try fetchSingle(ExportChild.self, from: context)
        let body = syncContainer.export(model)
        XCTAssertNil(body["parent"])
    }

    @MainActor
    func testExportNilToOneRelationshipAlwaysEmitsNSNull() throws {
        let syncContainer = try makeSyncContainer(for: ExportUser.self, ExportCompany.self, ExportNote.self)
        let context = syncContainer.mainContext
        context.insert(ExportUser(id: 8, name: "NoCompany", company: nil, notes: []))
        try context.save()

        let user = try fetchSingle(ExportUser.self, from: context)
        let body = syncContainer.export(user)
        XCTAssertTrue(body["company"] is NSNull, "Nil to-one relationship must always emit NSNull")
    }

    @MainActor
    func testExportNilOptionalsAlwaysEmitNSNull() throws {
        let syncContainer = try makeSyncContainer(for: ExportTask.self)
        let context = syncContainer.mainContext
        context.insert(ExportTask(id: 3, completed: false, createdAt: Date(timeIntervalSince1970: 0), nickname: nil))
        try context.save()

        let task = try fetchSingle(ExportTask.self, from: context)
        let body = syncContainer.export(task)
        XCTAssertTrue(body["nickname"] is NSNull, "Nil optional scalar must always emit NSNull")
    }

    /// Scenario A — PATCH with explicit null to clear a field.
    /// exportObject always emits NSNull for nil optionals. Callers can then overwrite specific
    /// fields with NSNull() to signal "clear this field", or overwrite with a new value.
    /// Both result in the key being present in the body — the intended behavior for partial-update APIs.
    @MainActor
    func testExportNilFieldCanBeExplicitlyClearedAfterExport() throws {
        let schema = Schema([ExportTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: config)
        let syncContainer = SyncContainer(modelContainer)
        let context = syncContainer.mainContext

        // A task with nickname already nil in the model
        context.insert(ExportTask(id: 10, completed: false, createdAt: Date(timeIntervalSince1970: 0), nickname: nil))
        try context.save()
        let task = try context.fetch(FetchDescriptor<ExportTask>()).first!

        // Export produces NSNull for nickname automatically — no manual NSNull() needed
        let body = syncContainer.export(task)
        XCTAssertTrue(body["nickname"] is NSNull,
                      "Nil optional must appear as NSNull in body so server clears the field")

        // Caller can still override any key after export (e.g. to set a new value)
        var mutableBody = body
        mutableBody["nickname"] = "new-name"
        XCTAssertEqual(mutableBody["nickname"] as? String, "new-name")
    }

    @MainActor
    func testExportCustomDateFormatter() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"

        let syncContainer = try makeSyncContainer(for: ExportTask.self, dateFormatter: formatter)
        let context = syncContainer.mainContext
        context.insert(ExportTask(id: 4, completed: true, createdAt: Date(timeIntervalSince1970: 0)))
        try context.save()

        let task = try fetchSingle(ExportTask.self, from: context)
        let body = syncContainer.export(task)
        XCTAssertEqual(body["created_at"] as? String, "1970/01/01")
    }

    @MainActor
    func testExportRecursionGuardAvoidsLoopCrash() throws {
        let syncContainer = try makeSyncContainer(for: CycleNode.self)
        let context = syncContainer.mainContext
        let root = CycleNode(id: 1, name: "root")
        let child = CycleNode(id: 2, name: "child", parent: root)
        root.parent = child
        context.insert(root)
        context.insert(child)
        try context.save()

        let rootBody = syncContainer.export(root)
        let childBody = syncContainer.export(child)
        XCTAssertEqual(rootBody["id"] as? Int, 1)
        XCTAssertEqual(childBody["id"] as? Int, 2)
    }

    // MARK: - Update body via export

    /// Regression: buildUpdateBody must use @RemoteKey mappings,
    /// not raw Swift property names. This mirrors the pattern used in DemoSyncEngine
    /// for createTask and must apply equally to updateTask.
    @MainActor
    func testBuildUpdateBodyUsesRemoteKeyMappings() throws {
        // ExportMappedFields has @RemoteKey("type") on userType and @RemoteKey("profile.contact.email") on email.
        // Simulate the buildUpdateBody pattern: transient model → exportObject → inspect keys.
        let schema = Schema([ExportMappedFields.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let model = ExportMappedFields(id: 42, userType: "editor", email: "update@example.com", localOnly: "ignored")
        context.insert(model)

        let body = model.export(
            keyStyle: .snakeCase,
            dateFormatter: defaultExportDateFormatter()
        )

        // @RemoteKey("type") must appear as "type", not "user_type"
        XCTAssertEqual(body["type"] as? String, "editor", "Expected @RemoteKey(\"type\") to map userType → \"type\"")
        XCTAssertNil(body["user_type"], "Raw snake_case key must not appear when @RemoteKey overrides it")

        // @RemoteKey("profile.contact.email") must appear nested
        let profile = body["profile"] as? [String: Any]
        let contact = profile?["contact"] as? [String: Any]
        XCTAssertEqual(contact?["email"] as? String, "update@example.com",
                       "Expected @RemoteKey(\"profile.contact.email\") to produce nested structure")
        XCTAssertNil(body["email"], "Flat key must not appear when nested @RemoteKey overrides it")

        // @NotExport field must be absent
        XCTAssertNil(body["local_only"], "@NotExport field must be excluded from update body")
        XCTAssertNil(body["localOnly"], "@NotExport field must be excluded from update body (camelCase variant)")
    }

    /// Regression: buildUpdateBody for a Task-like model must use @RemoteKey("description")
    /// for descriptionText and nested state dict for @RemoteKey("state.id") / @RemoteKey("state.label").
    /// This is the exact mapping gap that existed before update adopted export.
    @MainActor
    func testBuildUpdateBodyUsesRemoteKeyForTaskLikeModel() throws {
        let schema = Schema([UpdateTaskLike.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let model = UpdateTaskLike(
            id: "task-1",
            descriptionText: "Updated body text",
            state: "inProgress",
            stateLabel: "In Progress"
        )
        context.insert(model)

        let body = model.export(
            keyStyle: .snakeCase,
            dateFormatter: defaultExportDateFormatter()
        )

        // descriptionText → @RemoteKey("description") → must appear as "description"
        XCTAssertEqual(body["description"] as? String, "Updated body text",
                       "Expected @RemoteKey(\"description\") to map descriptionText → \"description\"")
        XCTAssertNil(body["description_text"],
                     "Raw snake_case key must not appear when @RemoteKey overrides it")
        XCTAssertNil(body["descriptionText"],
                     "Camel-case key must not appear when @RemoteKey overrides it")

        // state → @RemoteKey("state.id") → must appear nested under "state" dict
        let stateDict = body["state"] as? [String: Any]
        XCTAssertEqual(stateDict?["id"] as? String, "inProgress",
                       "Expected @RemoteKey(\"state.id\") to produce nested state.id")
        XCTAssertEqual(stateDict?["label"] as? String, "In Progress",
                       "Expected @RemoteKey(\"state.label\") to produce nested state.label")
        XCTAssertNil(body["state_id"], "Flat state_id key must not appear")
        XCTAssertNil(body["state_label"], "Flat state_label key must not appear")
    }

    // MARK: - SyncContainer.export(_:) derives keyStyle and dateFormatter from SyncContainer

    @MainActor
    func testExportForContainerDerivesKeyStyleFromContainer() throws {
        let schema = Schema([ExportTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: config)
        let syncContainer = SyncContainer(modelContainer, keyStyle: .camelCase)
        let context = syncContainer.mainContext

        context.insert(ExportTask(id: 5, completed: false, createdAt: Date(timeIntervalSince1970: 0)))
        try context.save()

        let task = try context.fetch(FetchDescriptor<ExportTask>()).first!
        let body = syncContainer.export(task)

        // camelCase keyStyle from container: createdAt, not created_at
        XCTAssertNotNil(body["createdAt"], "Expected camelCase key from container.keyStyle")
        XCTAssertNil(body["created_at"], "Snake_case key must not appear when container uses camelCase")
    }

    @MainActor
    func testExportForContainerDerivesDateFormatterFromContainer() throws {
        let schema = Schema([ExportTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: config)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        let syncContainer = SyncContainer(modelContainer, dateFormatter: formatter)
        let context = syncContainer.mainContext

        context.insert(ExportTask(id: 6, completed: false, createdAt: Date(timeIntervalSince1970: 0)))
        try context.save()

        let task = try context.fetch(FetchDescriptor<ExportTask>()).first!
        let body = syncContainer.export(task)

        XCTAssertEqual(body["created_at"] as? String, "1970/01/01",
                       "Expected date formatted using container.dateFormatter")
    }

    @MainActor
    private func makeSyncContainer(
        for models: any PersistentModel.Type...,
        keyStyle: KeyStyle = .snakeCase,
        dateFormatter: DateFormatter? = nil
    ) throws -> SyncContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(models)
        let modelContainer = try ModelContainer(for: schema, configurations: configuration)
        return SyncContainer(modelContainer, keyStyle: keyStyle, dateFormatter: dateFormatter)
    }

    @MainActor
    private func fetchSingle<Model: PersistentModel>(_ modelType: Model.Type, from context: ModelContext) throws -> Model {
        let rows = try context.fetch(FetchDescriptor<Model>())
        XCTAssertEqual(rows.count, 1)
        return try XCTUnwrap(rows.first)
    }
}
