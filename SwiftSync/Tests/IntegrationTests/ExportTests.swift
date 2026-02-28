import XCTest
import SwiftData
import SwiftSync

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
final class ExportMappedFields {
    @Attribute(.unique) var id: Int
    @RemoteKey("type") var userType: String
    @RemotePath("profile.contact.email") var email: String?
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

/// A Task-like model used to test that update bodies via exportObject
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

// Compile-time regression: exportObject must be a requirement of SyncUpdatableModel,
// not a separate ExportModel protocol. This function would not compile if exportObject
// were missing from SyncUpdatableModel.
private func _assertExportObjectIsOnSyncUpdatableModel<M: SyncUpdatableModel>(
    _ model: M,
    options: ExportOptions,
    state: inout ExportState
) -> [String: Any] {
    model.exportObject(using: options, state: &state)
}

final class ExportTests: XCTestCase {
    @MainActor
    func testExportDefaultsSnakeCaseAndISODate() throws {
        let context = try makeContext(for: ExportTask.self)
        context.insert(ExportTask(id: 9, completed: false, createdAt: Date(timeIntervalSince1970: 1_700_000_000)))
        try context.save()

        let rows = try SwiftSync.export(as: ExportTask.self, in: context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["id"] as? Int, 9)
        XCTAssertEqual(rows[0]["completed"] as? Bool, false)
        XCTAssertNotNil(rows[0]["created_at"] as? String)
    }

    @MainActor
    func testExportCamelCaseKeys() throws {
        let context = try makeContext(for: ExportTask.self)
        context.insert(ExportTask(id: 1, completed: true, createdAt: Date(timeIntervalSince1970: 0)))
        try context.save()

        var options = ExportOptions.camelCase
        options.includeNulls = false
        let rows = try SwiftSync.export(as: ExportTask.self, in: context, using: options)
        XCTAssertNotNil(rows[0]["createdAt"])
        XCTAssertNil(rows[0]["created_at"])
    }

    @MainActor
    func testExportSnakeCaseNormalizesAcronyms() throws {
        let context = try makeContext(for: ExportAcronymRecord.self)
        context.insert(ExportAcronymRecord(id: 1, projectID: "P-100"))
        try context.save()

        let rows = try SwiftSync.export(as: ExportAcronymRecord.self, in: context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["project_id"] as? String, "P-100")
        XCTAssertNil(rows[0]["project_i_d"])
    }

    @MainActor
    func testExportPrimaryKeyRemoteMapping() throws {
        let context = try makeContext(for: ExportRemotePrimary.self)
        context.insert(ExportRemotePrimary(xid: "abc", name: "n"))
        try context.save()

        let rows = try SwiftSync.export(as: ExportRemotePrimary.self, in: context)
        XCTAssertEqual(rows[0]["external_id"] as? String, "abc")
        XCTAssertNil(rows[0]["xid"])
    }

    @MainActor
    func testExportNotExportRemoteKeyAndRemotePath() throws {
        let context = try makeContext(for: ExportMappedFields.self)
        context.insert(ExportMappedFields(id: 2, userType: "admin", email: "a@b.com", localOnly: "secret"))
        try context.save()

        let rows = try SwiftSync.export(as: ExportMappedFields.self, in: context)
        let row = rows[0]
        XCTAssertEqual(row["type"] as? String, "admin")
        XCTAssertNil(row["user_type"])
        XCTAssertNil(row["local_only"])

        let profile = row["profile"] as? [String: Any]
        let contact = profile?["contact"] as? [String: Any]
        XCTAssertEqual(contact?["email"] as? String, "a@b.com")
    }

    @MainActor
    func testExportRelationshipModesArrayNestedNone() throws {
        let context = try makeContext(for: ExportUser.self, ExportCompany.self, ExportNote.self)
        let company = ExportCompany(id: 7, name: "Acme")
        let note0 = ExportNote(id: 10, text: "n0")
        let note1 = ExportNote(id: 11, text: "n1")
        context.insert(company)
        context.insert(note0)
        context.insert(note1)
        context.insert(ExportUser(id: 1, name: "U", company: company, notes: [note0, note1]))
        try context.save()

        let arrayRows = try SwiftSync.export(as: ExportUser.self, in: context)
        let arrayRow = arrayRows[0]
        XCTAssertEqual((arrayRow["company"] as? [String: Any])?["id"] as? Int, 7)
        XCTAssertEqual((arrayRow["notes"] as? [[String: Any]])?.count, 2)

        var nestedOptions = ExportOptions()
        nestedOptions.relationshipMode = .nested
        let nestedRows = try SwiftSync.export(as: ExportUser.self, in: context, using: nestedOptions)
        let nestedRow = nestedRows[0]
        XCTAssertEqual((nestedRow["company_attributes"] as? [String: Any])?["id"] as? Int, 7)
        let notesAttributes = nestedRow["notes_attributes"] as? [String: [String: Any]]
        XCTAssertEqual(notesAttributes?.count, 2)
        let nestedIDs = Set((notesAttributes ?? [:]).values.compactMap { $0["id"] as? Int })
        XCTAssertEqual(nestedIDs, Set([10, 11]))

        let noneRows = try SwiftSync.export(as: ExportUser.self, in: context, using: .excludedRelationships)
        XCTAssertNil(noneRows[0]["company"])
        XCTAssertNil(noneRows[0]["notes"])
    }

    @MainActor
    func testExportRemotePathNilIncludesAndOmitsNullByOption() throws {
        let context = try makeContext(for: ExportMappedFields.self)
        context.insert(ExportMappedFields(id: 3, userType: "member", email: nil, localOnly: "secret"))
        try context.save()

        let withNulls = try SwiftSync.export(as: ExportMappedFields.self, in: context)
        let withNullProfile = withNulls[0]["profile"] as? [String: Any]
        let withNullContact = withNullProfile?["contact"] as? [String: Any]
        XCTAssertTrue(withNullContact?["email"] is NSNull)

        var withoutNullsOptions = ExportOptions()
        withoutNullsOptions.includeNulls = false
        let withoutNulls = try SwiftSync.export(as: ExportMappedFields.self, in: context, using: withoutNullsOptions)
        XCTAssertNil(withoutNulls[0]["profile"])
    }

    @MainActor
    func testExportNotExportRelationshipOmitsRelationshipKey() throws {
        let context = try makeContext(for: ExportParent.self, ExportChild.self)
        let parent = ExportParent(id: 9, name: "P")
        let child = ExportChild(id: 1, text: "c1", parent: parent)
        context.insert(parent)
        context.insert(child)
        try context.save()

        let rows = try SwiftSync.export(as: ExportChild.self, in: context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0]["parent"])
    }

    @MainActor
    func testExportToOneNilRespectsIncludeNulls() throws {
        let context = try makeContext(for: ExportUser.self, ExportCompany.self, ExportNote.self)
        context.insert(ExportUser(id: 8, name: "NoCompany", company: nil, notes: []))
        try context.save()

        let withNulls = try SwiftSync.export(as: ExportUser.self, in: context)
        XCTAssertTrue(withNulls[0]["company"] is NSNull)

        var options = ExportOptions()
        options.includeNulls = false
        let withoutNulls = try SwiftSync.export(as: ExportUser.self, in: context, using: options)
        XCTAssertNil(withoutNulls[0]["company"])
    }

    @MainActor
    func testExportIncludeNullsBehavior() throws {
        let context = try makeContext(for: ExportTask.self)
        context.insert(ExportTask(id: 3, completed: false, createdAt: Date(timeIntervalSince1970: 0), nickname: nil))
        try context.save()

        let withNulls = try SwiftSync.export(as: ExportTask.self, in: context)
        XCTAssertTrue(withNulls[0]["nickname"] is NSNull)

        var withoutNullsOptions = ExportOptions()
        withoutNullsOptions.includeNulls = false
        let withoutNulls = try SwiftSync.export(as: ExportTask.self, in: context, using: withoutNullsOptions)
        XCTAssertNil(withoutNulls[0]["nickname"])
    }

    @MainActor
    func testExportCustomDateFormatter() throws {
        let context = try makeContext(for: ExportTask.self)
        context.insert(ExportTask(id: 4, completed: true, createdAt: Date(timeIntervalSince1970: 0)))
        try context.save()

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        var options = ExportOptions()
        options.dateFormatter = formatter
        let rows = try SwiftSync.export(as: ExportTask.self, in: context, using: options)
        XCTAssertEqual(rows[0]["created_at"] as? String, "1970/01/01")
    }

    @MainActor
    func testExportParentScopedOnlyExportsThatParentsChildren() throws {
        let context = try makeContext(for: ExportParent.self, ExportChild.self)
        let parentA = ExportParent(id: 6, name: "A")
        let parentB = ExportParent(id: 7, name: "B")
        let a0 = ExportChild(id: 0, text: "a0", parent: parentA)
        let a1 = ExportChild(id: 1, text: "a1", parent: parentA)
        let b2 = ExportChild(id: 2, text: "b2", parent: parentB)
        context.insert(parentA)
        context.insert(parentB)
        context.insert(a0)
        context.insert(a1)
        context.insert(b2)
        try context.save()

        let rows = try SwiftSync.export(as: ExportChild.self, in: context, parent: parentA)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap { $0["id"] as? Int }), Set([0, 1]))
    }

    @MainActor
    func testExportRecursionGuardAvoidsLoopCrash() throws {
        let context = try makeContext(for: CycleNode.self)
        let root = CycleNode(id: 1, name: "root")
        let child = CycleNode(id: 2, name: "child", parent: root)
        root.parent = child
        context.insert(root)
        context.insert(child)
        try context.save()

        let rows = try SwiftSync.export(as: CycleNode.self, in: context)
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotNil(rows.first(where: { ($0["id"] as? Int) == 1 }))
    }

    // MARK: - Update body via export

    /// Regression: buildUpdateBody must use @RemoteKey and @RemotePath mappings,
    /// not raw Swift property names. This mirrors the pattern used in DemoSyncEngine
    /// for createTask and must apply equally to updateTask.
    @MainActor
    func testBuildUpdateBodyUsesRemoteKeyMappings() throws {
        // ExportMappedFields has @RemoteKey("type") on userType and @RemotePath("profile.contact.email") on email.
        // Simulate the buildUpdateBody pattern: transient model → exportObject → inspect keys.
        let schema = Schema([ExportMappedFields.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let model = ExportMappedFields(id: 42, userType: "editor", email: "update@example.com", localOnly: "ignored")
        context.insert(model)

        var exportState = ExportState()
        let options = ExportOptions(relationshipMode: .none, includeNulls: false)
        let body = model.exportObject(using: options, state: &exportState)

        // @RemoteKey("type") must appear as "type", not "user_type"
        XCTAssertEqual(body["type"] as? String, "editor", "Expected @RemoteKey(\"type\") to map userType → \"type\"")
        XCTAssertNil(body["user_type"], "Raw snake_case key must not appear when @RemoteKey overrides it")

        // @RemotePath("profile.contact.email") must appear nested
        let profile = body["profile"] as? [String: Any]
        let contact = profile?["contact"] as? [String: Any]
        XCTAssertEqual(contact?["email"] as? String, "update@example.com",
                       "Expected @RemotePath(\"profile.contact.email\") to produce nested structure")
        XCTAssertNil(body["email"], "Flat key must not appear when @RemotePath overrides it")

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

        var exportState = ExportState()
        let options = ExportOptions(relationshipMode: .none, includeNulls: false)
        let body = model.exportObject(using: options, state: &exportState)

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

    @MainActor
    private func makeContext(for models: any PersistentModel.Type...) throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(models)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
