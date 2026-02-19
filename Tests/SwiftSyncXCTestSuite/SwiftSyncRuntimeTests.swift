import XCTest
import SwiftData
import SwiftSyncCore
import SwiftSyncMacros
import SwiftSyncSwiftData

@Syncable
@Model
final class RuntimeUser {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class RuntimeLooseUser {
    var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class RuntimeRemoteUser {
    @Attribute(.unique) var remoteID: Int
    var fullName: String

    init(remoteID: Int, fullName: String) {
        self.remoteID = remoteID
        self.fullName = fullName
    }
}

@Syncable
@Model
final class RuntimeExternalUser {
    @PrimaryKey
    @Attribute(.unique) var xid: String
    var name: String

    init(xid: String, name: String) {
        self.xid = xid
        self.name = name
    }
}

@Syncable
@Model
final class RuntimeProfile {
    @Attribute(.unique) var id: Int
    var firstName: String
    var updatedAt: Date

    init(id: Int, firstName: String, updatedAt: Date) {
        self.id = id
        self.firstName = firstName
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class RuntimeOptionalDateProfile {
    @Attribute(.unique) var id: Int
    var updatedAt: Date?

    init(id: Int, updatedAt: Date?) {
        self.id = id
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class RuntimePrimitiveUser {
    @Attribute(.unique) var id: Int
    var name: String
    var age: Int
    var score: Double
    var isActive: Bool
    var updatedAt: Date
    var token: UUID
    var bigCount: Int64
    var nickname: String?

    init(
        id: Int,
        name: String,
        age: Int,
        score: Double,
        isActive: Bool,
        updatedAt: Date,
        token: UUID,
        bigCount: Int64,
        nickname: String?
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.score = score
        self.isActive = isActive
        self.updatedAt = updatedAt
        self.token = token
        self.bigCount = bigCount
        self.nickname = nickname
    }
}

@Syncable
@Model
final class RuntimeExternalMappedUser {
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
final class RuntimeStringIDUser {
    @Attribute(.unique) var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class RuntimeMember {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Model
final class RuntimeTeam {
    @Attribute(.unique) var id: Int
    var name: String
    var owner: RuntimeMember?
    var members: [RuntimeMember]

    init(id: Int, name: String, owner: RuntimeMember? = nil, members: [RuntimeMember] = []) {
        self.id = id
        self.name = name
        self.owner = owner
        self.members = members
    }
}

@Model
final class RuntimeCompany {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class RuntimeEmployee {
    @Attribute(.unique) var id: Int
    var name: String
    var company: RuntimeCompany?

    init(id: Int, name: String, company: RuntimeCompany? = nil) {
        self.id = id
        self.name = name
        self.company = company
    }
}

@Model
final class RuntimeNote {
    @Attribute(.unique) var id: Int
    var text: String

    init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

@Model
final class RuntimeUserWithNotes {
    @Attribute(.unique) var id: Int
    var name: String
    var notes: [RuntimeNote]

    init(id: Int, name: String, notes: [RuntimeNote] = []) {
        self.id = id
        self.name = name
        self.notes = notes
    }
}

@Model
final class RuntimeTag {
    @Attribute(.unique) var id: Int
    var name: String
    var usersByObjects: [RuntimeUserTagsByObjects]
    var usersByIDs: [RuntimeUserTagsByIDs]

    init(id: Int, name: String) {
        self.id = id
        self.name = name
        self.usersByObjects = []
        self.usersByIDs = []
    }
}

@Model
final class RuntimeUserTagsByObjects {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \RuntimeTag.usersByObjects)
    var tags: [RuntimeTag]

    init(id: Int, name: String, tags: [RuntimeTag] = []) {
        self.id = id
        self.name = name
        self.tags = tags
    }
}

@Model
final class RuntimeUserTagsByIDs {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \RuntimeTag.usersByIDs)
    var tags: [RuntimeTag]

    init(id: Int, name: String, tags: [RuntimeTag] = []) {
        self.id = id
        self.name = name
        self.tags = tags
    }
}

extension RuntimeTeam: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeTeam, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeTeam {
        RuntimeTeam(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            return true
        }
        return false
    }
}

extension RuntimeTeam: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        var changed = false

        if payload.contains("owner") {
            let nextOwner: RuntimeMember?
            if let ownerPayload: [String: Any] = payload.value(for: "owner") {
                nextOwner = try upsertMember(from: ownerPayload, in: context)
            } else {
                nextOwner = nil
            }

            if owner?.id != nextOwner?.id {
                owner = nextOwner
                changed = true
            }
        }

        if payload.contains("members") {
            let desiredMembers: [RuntimeMember]
            if let memberPayloads: [[String: Any]] = payload.value(for: "members") {
                var resolvedMembers: [RuntimeMember] = []
                for memberPayload in memberPayloads {
                    resolvedMembers.append(try upsertMember(from: memberPayload, in: context))
                }
                desiredMembers = resolvedMembers
            } else {
                // Explicit null for members means clear membership.
                desiredMembers = []
            }
            if members.map(\.id) != desiredMembers.map(\.id) {
                members = desiredMembers
                changed = true
            }
        }

        return changed
    }

    private func upsertMember(from payload: [String: Any], in context: ModelContext) throws -> RuntimeMember {
        let syncPayload = SyncPayload(values: payload)
        let memberID: Int = try syncPayload.required(Int.self, for: "id")
        let allMembers = try context.fetch(FetchDescriptor<RuntimeMember>())
        if let existing = allMembers.first(where: { $0.id == memberID }) {
            _ = try existing.apply(syncPayload)
            return existing
        }
        let created = try RuntimeMember.make(from: syncPayload)
        context.insert(created)
        return created
    }
}

extension RuntimeCompany: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeCompany, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeCompany {
        RuntimeCompany(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension RuntimeEmployee: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeEmployee, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeEmployee {
        RuntimeEmployee(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension RuntimeEmployee: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        // Support to-one by foreign key scalar (company_id).
        guard payload.contains("company_id") else { return false }

        let companyID: Int? = payload.value(for: "company_id")
        if let companyID {
            let companies = try context.fetch(FetchDescriptor<RuntimeCompany>())
            let nextCompany = companies.first(where: { $0.id == companyID })
            if company?.id != nextCompany?.id {
                company = nextCompany
                return true
            }
            return false
        } else {
            if company != nil {
                company = nil
                return true
            }
            return false
        }
    }
}

extension RuntimeNote: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeNote, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeNote {
        RuntimeNote(
            id: try payload.required(Int.self, for: "id"),
            text: try payload.required(String.self, for: "text")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingText: String = try payload.required(String.self, for: "text")
        if text != incomingText {
            text = incomingText
            changed = true
        }
        return changed
    }
}

extension RuntimeUserWithNotes: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeUserWithNotes, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeUserWithNotes {
        RuntimeUserWithNotes(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension RuntimeUserWithNotes: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        // Support to-many by foreign key scalar array (notes_ids).
        guard payload.contains("notes_ids") else { return false }

        let desiredIDs: [Int]
        if let value: [Int] = payload.value(for: "notes_ids") {
            desiredIDs = value
        } else {
            desiredIDs = []
        }

        let allNotes = try context.fetch(FetchDescriptor<RuntimeNote>())
        let byID = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })
        let desiredNotes = desiredIDs.compactMap { byID[$0] }

        if notes.map(\.id) != desiredNotes.map(\.id) {
            notes = desiredNotes
            return true
        }
        return false
    }
}

extension RuntimeTag: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeTag, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeTag {
        RuntimeTag(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension RuntimeUserTagsByObjects: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeUserTagsByObjects, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeUserTagsByObjects {
        RuntimeUserTagsByObjects(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension RuntimeUserTagsByObjects: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        guard payload.contains("tags") else { return false }
        let desiredTags: [RuntimeTag]
        if let tagPayloads: [[String: Any]] = payload.value(for: "tags") {
            var resolved: [RuntimeTag] = []
            for tagPayload in tagPayloads {
                resolved.append(try upsertTag(from: tagPayload, in: context))
            }
            desiredTags = resolved
        } else {
            desiredTags = []
        }
        if tags.map(\.id) != desiredTags.map(\.id) {
            tags = desiredTags
            return true
        }
        return false
    }

    private func upsertTag(from payload: [String: Any], in context: ModelContext) throws -> RuntimeTag {
        let syncPayload = SyncPayload(values: payload)
        let tagID: Int = try syncPayload.required(Int.self, for: "id")
        let allTags = try context.fetch(FetchDescriptor<RuntimeTag>())
        if let existing = allTags.first(where: { $0.id == tagID }) {
            _ = try existing.apply(syncPayload)
            return existing
        }
        let created = try RuntimeTag.make(from: syncPayload)
        context.insert(created)
        return created
    }
}

extension RuntimeUserTagsByIDs: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<RuntimeUserTagsByIDs, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> RuntimeUserTagsByIDs {
        RuntimeUserTagsByIDs(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension RuntimeUserTagsByIDs: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        guard payload.contains("tags_ids") else { return false }
        let desiredIDs: [Int]
        if let ids: [Int] = payload.value(for: "tags_ids") {
            desiredIDs = ids
        } else {
            desiredIDs = []
        }
        let allTags = try context.fetch(FetchDescriptor<RuntimeTag>())
        let byID = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        let desiredTags = desiredIDs.compactMap { byID[$0] }
        if tags.map(\.id) != desiredTags.map(\.id) {
            tags = desiredTags
            return true
        }
        return false
    }
}

final class SwiftSyncRuntimeTests: XCTestCase {
    func testApplyReturnsFalseWhenPayloadMatchesExistingValues() throws {
        let user = RuntimeUser(id: 1, fullName: "Ava Swift")
        let payload = SyncPayload(values: ["id": 1, "full_name": "Ava Swift"])

        let changed = try user.apply(payload)

        XCTAssertFalse(changed)
        XCTAssertEqual(user.fullName, "Ava Swift")
    }

    func testApplyReturnsTrueWhenAnyFieldDiffers() throws {
        let user = RuntimeUser(id: 1, fullName: "Ava Swift")
        let payload = SyncPayload(values: ["id": 1, "full_name": "Ava Updated"])

        let changed = try user.apply(payload)

        XCTAssertTrue(changed)
        XCTAssertEqual(user.fullName, "Ava Updated")
    }

    @MainActor
    func testSyncInsertsThenUpdatesByID() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let insertPayload: [Any] = [["id": 1, "full_name": "Ava Swift"]]
        try await SwiftSync.sync(payload: insertPayload, as: RuntimeUser.self, in: context)

        var users = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.fullName, "Ava Swift")

        let updatePayload: [Any] = [["id": 1, "full_name": "Ava Updated"]]
        try await SwiftSync.sync(payload: updatePayload, as: RuntimeUser.self, in: context)

        users = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.fullName, "Ava Updated")
    }

    @MainActor
    func testSyncUsesRemoteIDConvention() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeRemoteUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [["id": 55, "full_name": "Remote User"]]
        try await SwiftSync.sync(payload: payload, as: RuntimeRemoteUser.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeRemoteUser>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.remoteID, 55)
        XCTAssertEqual(users.first?.fullName, "Remote User")
    }

    @MainActor
    func testSyncLenientIntPrimaryKeyCoercesFloatValue() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [["id": 42.9, "full_name": "Float ID User"]]
        try await SwiftSync.sync(payload: payload, as: RuntimeUser.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, 42)
        XCTAssertEqual(users.first?.fullName, "Float ID User")
    }

    @MainActor
    func testSyncCoercesStringIDToIntAndMatchesLaterNumericID() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["id": "42", "full_name": "X"]]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeUser.self, in: context)

        var rows = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 42)

        let payloadB: [Any] = [["id": 42, "full_name": "X Updated"]]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeUser.self, in: context)

        rows = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 42)
        XCTAssertEqual(rows.first?.fullName, "X Updated")
    }

    @MainActor
    func testSyncCoercesNumericIDToStringAndMatchesLaterStringID() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeStringIDUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["id": 42, "name": "X"]]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeStringIDUser.self, in: context)

        var rows = try context.fetch(FetchDescriptor<RuntimeStringIDUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "42")
        XCTAssertEqual(rows.first?.name, "X")

        let payloadB: [Any] = [["id": "42", "name": "X Updated"]]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeStringIDUser.self, in: context)

        rows = try context.fetch(FetchDescriptor<RuntimeStringIDUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "42")
        XCTAssertEqual(rows.first?.name, "X Updated")
    }

    @MainActor
    func testSyncSnakeCaseToCamelCaseWithISO8601Date() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeProfile.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [[
            "id": 1,
            "first_name": "Elvis",
            "updated_at": "2014-02-17T00:00:00+00:00"
        ]]
        try await SwiftSync.sync(payload: payload, as: RuntimeProfile.self, in: context)
        try await SwiftSync.sync(payload: payload, as: RuntimeProfile.self, in: context)

        let rows = try context.fetch(FetchDescriptor<RuntimeProfile>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.firstName, "Elvis")
        XCTAssertEqual(rows.first?.updatedAt, ISO8601DateFormatter().date(from: "2014-02-17T00:00:00+00:00"))
    }

    @MainActor
    func testSyncParsesDateOnlyISOFormat() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeProfile.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [[
            "id": 1,
            "first_name": "Elvis",
            "updated_at": "2014-01-02"
        ]]
        try await SwiftSync.sync(payload: payload, as: RuntimeProfile.self, in: context)

        let rows = try context.fetch(FetchDescriptor<RuntimeProfile>())
        XCTAssertEqual(rows.count, 1)

        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2014
        components.month = 1
        components.day = 2
        components.hour = 0
        components.minute = 0
        components.second = 0
        XCTAssertEqual(rows.first?.updatedAt, components.date)
    }

    @MainActor
    func testSyncParsesUnixTimestampVariants() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeProfile.self, configurations: configuration)
        let context = ModelContext(container)

        // Seconds
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "A",
                "updated_at": 1_700_000_000
            ]],
            as: RuntimeProfile.self,
            in: context
        )
        var rows = try context.fetch(FetchDescriptor<RuntimeProfile>())
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))

        // Milliseconds
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "A",
                "updated_at": 1_700_000_000_000
            ]],
            as: RuntimeProfile.self,
            in: context
        )
        rows = try context.fetch(FetchDescriptor<RuntimeProfile>())
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))

        // Microseconds
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "A",
                "updated_at": 1_700_000_000_000_000
            ]],
            as: RuntimeProfile.self,
            in: context
        )
        rows = try context.fetch(FetchDescriptor<RuntimeProfile>())
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    @MainActor
    func testSyncInvalidDateDefaultsRequiredAndNilForOptional() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeProfile.self, RuntimeOptionalDateProfile.self, configurations: configuration)
        let context = ModelContext(container)

        // Required Date field defaults to epoch on invalid input.
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "Elvis",
                "updated_at": "not-a-date"
            ]],
            as: RuntimeProfile.self,
            in: context
        )
        let requiredRows = try context.fetch(FetchDescriptor<RuntimeProfile>())
        XCTAssertEqual(requiredRows.count, 1)
        XCTAssertEqual(requiredRows.first?.updatedAt, Date(timeIntervalSince1970: 0))

        // Optional Date field stays nil on invalid input.
        try await SwiftSync.sync(
            payload: [[
                "id": 2,
                "updated_at": "not-a-date"
            ]],
            as: RuntimeOptionalDateProfile.self,
            in: context
        )
        let optionalRows = try context.fetch(FetchDescriptor<RuntimeOptionalDateProfile>())
        XCTAssertEqual(optionalRows.count, 1)
        XCTAssertNil(optionalRows.first?.updatedAt)
    }

    @MainActor
    func testSyncNullClearsNonOptionalPrimitiveScalarsToDefaults() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimePrimitiveUser.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 1,
            "name": "Alice",
            "age": 40,
            "score": 99.5,
            "is_active": true,
            "updated_at": "2014-02-17T00:00:00+00:00",
            "token": "123E4567-E89B-12D3-A456-426614174000",
            "big_count": Int64(77),
            "nickname": "Al"
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimePrimitiveUser.self, in: context)

        let clearPayload: [Any] = [[
            "id": 1,
            "name": NSNull(),
            "age": NSNull(),
            "score": NSNull(),
            "is_active": NSNull(),
            "updated_at": NSNull(),
            "token": NSNull(),
            "big_count": NSNull(),
            "nickname": NSNull()
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: RuntimePrimitiveUser.self, in: context)

        let rows = try context.fetch(FetchDescriptor<RuntimePrimitiveUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "")
        XCTAssertEqual(rows.first?.age, 0)
        XCTAssertEqual(rows.first?.score, 0.0)
        XCTAssertEqual(rows.first?.isActive, false)
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(rows.first?.token.uuidString, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(rows.first?.bigCount, 0)
        XCTAssertNil(rows.first?.nickname)
    }

    @MainActor
    func testSyncDeletesLocalRowsMissingFromPayload() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [
            ["id": 1, "full_name": "Ava Swift"],
            ["id": 2, "full_name": "Noah Swift"]
        ]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimeUser.self, in: context)

        let replacePayload: [Any] = [["id": 1, "full_name": "Ava Updated"]]
        try await SwiftSync.sync(payload: replacePayload, as: RuntimeUser.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, 1)
        XCTAssertEqual(users.first?.fullName, "Ava Updated")
    }

    @MainActor
    func testSyncPrimaryKeyDiffingInsertUpdateDeleteInSingleRun() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [
            ["id": 0, "full_name": "User 0"],
            ["id": 1, "full_name": "User 1"],
            ["id": 2, "full_name": "User 2"],
            ["id": 3, "full_name": "User 3"],
            ["id": 4, "full_name": "User 4"]
        ]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimeUser.self, in: context)

        let diffPayload: [Any] = [
            ["id": 0, "full_name": "User 0 Updated"],
            ["id": 1, "full_name": "User 1 Updated"],
            ["id": 6, "full_name": "User 6 New"]
        ]
        try await SwiftSync.sync(payload: diffPayload, as: RuntimeUser.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(users.count, 3)

        let ids = Set(users.map(\.id))
        XCTAssertEqual(ids, Set([0, 1, 6]))
        XCTAssertEqual(users.filter { $0.id == 0 }.count, 1)
        XCTAssertEqual(users.filter { $0.id == 1 }.count, 1)
        XCTAssertEqual(users.filter { $0.id == 6 }.count, 1)

        XCTAssertEqual(users.first(where: { $0.id == 0 })?.fullName, "User 0 Updated")
        XCTAssertEqual(users.first(where: { $0.id == 1 })?.fullName, "User 1 Updated")
        XCTAssertEqual(users.first(where: { $0.id == 6 })?.fullName, "User 6 New")
    }

    @MainActor
    func testSyncDeduplicatesLocalDuplicatePrimaryKeys() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeLooseUser.self, configurations: configuration)
        let context = ModelContext(container)

        context.insert(RuntimeLooseUser(id: 1, fullName: "dup-a"))
        context.insert(RuntimeLooseUser(id: 1, fullName: "dup-b"))
        context.insert(RuntimeLooseUser(id: 1, fullName: "dup-c"))
        context.insert(RuntimeLooseUser(id: 2, fullName: "other"))
        try context.save()

        let payload: [Any] = [["id": 1, "full_name": "single"]]
        do {
            try await SwiftSync.sync(payload: payload, as: RuntimeLooseUser.self, in: context)
        } catch {
            XCTFail("Expected sync to dedupe local duplicates without crashing, got error: \(error)")
        }

        let rows = try context.fetch(FetchDescriptor<RuntimeLooseUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.filter { $0.id == 1 }.count, 1)
        XCTAssertEqual(rows.first?.id, 1)
        XCTAssertEqual(rows.first?.fullName, "single")
    }

    @MainActor
    func testSyncUsesCustomPrimaryKeyWithoutIDField() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeExternalUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["xid": "abc", "name": "v1"]]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeExternalUser.self, in: context)

        let payloadB: [Any] = [["xid": "abc", "name": "v2"]]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeExternalUser.self, in: context)

        let rows = try context.fetch(FetchDescriptor<RuntimeExternalUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.xid, "abc")
        XCTAssertEqual(rows.first?.name, "v2")
    }

    @MainActor
    func testSyncUsesCustomPrimaryKeyWithRemoteKeyMapping() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeExternalMappedUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["external_id": "abc", "name": "v1"]]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeExternalMappedUser.self, in: context)

        let payloadB: [Any] = [["external_id": "abc", "name": "v2"]]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeExternalMappedUser.self, in: context)

        let rows = try context.fetch(FetchDescriptor<RuntimeExternalMappedUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.xid, "abc")
        XCTAssertEqual(rows.first?.name, "v2")
    }

    @MainActor
    func testSyncSkipsRowsWithNullOrMissingIdentity() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [
            ["id": 1, "full_name": "One"],
            ["id": 2, "full_name": "Two"]
        ]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimeUser.self, in: context)

        let mixedPayload: [Any] = [
            ["id": NSNull(), "full_name": "Null ID"],
            ["full_name": "Missing ID"],
            ["id": 1, "full_name": "One Updated"]
        ]

        do {
            try await SwiftSync.sync(payload: mixedPayload, as: RuntimeUser.self, in: context)
        } catch {
            XCTFail("Expected sync to skip invalid identity rows, got error: \(error)")
        }

        let users = try context.fetch(FetchDescriptor<RuntimeUser>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, 1)
        XCTAssertEqual(users.first?.fullName, "One Updated")
    }

    @MainActor
    func testSyncRelationshipsApplyToOneAndToMany() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeTeam.self, RuntimeMember.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 10,
            "name": "Platform",
            "owner": ["id": 1, "full_name": "Owner A"],
            "members": [
                ["id": 1, "full_name": "Owner A"],
                ["id": 2, "full_name": "Member B"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimeTeam.self, in: context)

        let updatePayload: [Any] = [[
            "id": 10,
            "name": "Platform Updated",
            "owner": ["id": 2, "full_name": "Member B Updated"],
            "members": [
                ["id": 2, "full_name": "Member B Updated"],
                ["id": 3, "full_name": "Member C"]
            ]
        ]]
        try await SwiftSync.sync(payload: updatePayload, as: RuntimeTeam.self, in: context)

        let teams = try context.fetch(FetchDescriptor<RuntimeTeam>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(teams.first?.name, "Platform Updated")
        XCTAssertEqual(teams.first?.owner?.id, 2)
        XCTAssertEqual(teams.first?.members.map(\.id), [2, 3])
    }

    @MainActor
    func testSyncRelationshipsClearWithNullAndEmptyCollection() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeTeam.self, RuntimeMember.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 11,
            "name": "Platform",
            "owner": ["id": 1, "full_name": "Owner A"],
            "members": [
                ["id": 1, "full_name": "Owner A"],
                ["id": 2, "full_name": "Member B"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimeTeam.self, in: context)

        let clearPayload: [Any] = [[
            "id": 11,
            "name": "Platform",
            "owner": NSNull(),
            "members": []
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: RuntimeTeam.self, in: context)

        let teams = try context.fetch(FetchDescriptor<RuntimeTeam>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertNil(teams.first?.owner)
        XCTAssertEqual(teams.first?.members.count, 0)
    }

    @MainActor
    func testSyncToManyObjectArrayEmptyClearsRelationshipSet() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUserTagsByObjects.self, RuntimeTag.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 1,
            "name": "U1",
            "tags": [
                ["id": 10, "name": "t10"],
                ["id": 11, "name": "t11"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimeUserTagsByObjects.self, in: context)

        let clearPayload: [Any] = [[
            "id": 1,
            "name": "U1",
            "tags": []
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: RuntimeUserTagsByObjects.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeUserTagsByObjects>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users[0].tags.count, 0)
    }

    @MainActor
    func testSyncToManyObjectArrayNullClearsRelationshipSetAndMatchesEmptySemantics() async throws {
        // Snapshot A: clear with empty array.
        let configurationA = ModelConfiguration(isStoredInMemoryOnly: true)
        let containerA = try ModelContainer(for: RuntimeUserTagsByObjects.self, RuntimeTag.self, configurations: configurationA)
        let contextA = ModelContext(containerA)
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 10, "name": "t10"],
                    ["id": 11, "name": "t11"]
                ]
            ]],
            as: RuntimeUserTagsByObjects.self,
            in: contextA
        )
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "U1",
                "tags": []
            ]],
            as: RuntimeUserTagsByObjects.self,
            in: contextA
        )
        let usersA = try contextA.fetch(FetchDescriptor<RuntimeUserTagsByObjects>())

        // Snapshot B: clear with null.
        let configurationB = ModelConfiguration(isStoredInMemoryOnly: true)
        let containerB = try ModelContainer(for: RuntimeUserTagsByObjects.self, RuntimeTag.self, configurations: configurationB)
        let contextB = ModelContext(containerB)
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 10, "name": "t10"],
                    ["id": 11, "name": "t11"]
                ]
            ]],
            as: RuntimeUserTagsByObjects.self,
            in: contextB
        )
        do {
            try await SwiftSync.sync(
                payload: [[
                    "id": 1,
                    "name": "U1",
                    "tags": NSNull()
                ]],
                as: RuntimeUserTagsByObjects.self,
                in: contextB
            )
        } catch {
            XCTFail("Expected null to clear to-many relationship without crashing, got error: \(error)")
        }
        let usersB = try contextB.fetch(FetchDescriptor<RuntimeUserTagsByObjects>())

        XCTAssertEqual(usersA.count, 1)
        XCTAssertEqual(usersB.count, 1)
        XCTAssertEqual(usersA[0].tags.count, 0)
        XCTAssertEqual(usersB[0].tags.count, 0)
        XCTAssertEqual(Set(usersA[0].tags.map(\.id)), Set(usersB[0].tags.map(\.id)))
    }

    @MainActor
    func testSyncRelationshipsMissingKeysPreserveExistingLinks() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeTeam.self, RuntimeMember.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 12,
            "name": "Platform",
            "owner": ["id": 1, "full_name": "Owner A"],
            "members": [
                ["id": 1, "full_name": "Owner A"],
                ["id": 2, "full_name": "Member B"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: RuntimeTeam.self, in: context)

        let nameOnlyPayload: [Any] = [[
            "id": 12,
            "name": "Platform Renamed"
        ]]
        try await SwiftSync.sync(payload: nameOnlyPayload, as: RuntimeTeam.self, in: context)

        let teams = try context.fetch(FetchDescriptor<RuntimeTeam>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(teams.first?.name, "Platform Renamed")
        XCTAssertEqual(teams.first?.owner?.id, 1)
        XCTAssertEqual(Set(teams.first?.members.map(\.id) ?? []), Set([1, 2]))
    }

    @MainActor
    func testSyncToOneByIDSetsAndClearsRelationship() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeEmployee.self, RuntimeCompany.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "Apple"]],
            as: RuntimeCompany.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava"]],
            as: RuntimeEmployee.self,
            in: context
        )

        let linkPayload: [Any] = [[
            "id": 1,
            "name": "Ava",
            "company_id": 10
        ]]
        try await SwiftSync.sync(payload: linkPayload, as: RuntimeEmployee.self, in: context)

        var employees = try context.fetch(FetchDescriptor<RuntimeEmployee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertEqual(employees.first?.id, 1)
        XCTAssertEqual(employees.first?.company?.id, 10)

        let clearPayload: [Any] = [[
            "id": 1,
            "name": "Ava",
            "company_id": NSNull()
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: RuntimeEmployee.self, in: context)

        employees = try context.fetch(FetchDescriptor<RuntimeEmployee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertNil(employees.first?.company)
    }

    @MainActor
    func testSyncToOneByIDMissingReferencedCompanyIsDeterministic() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeEmployee.self, RuntimeCompany.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava"]],
            as: RuntimeEmployee.self,
            in: context
        )

        let missingReferencePayload: [Any] = [[
            "id": 1,
            "name": "Ava",
            "company_id": 999
        ]]
        do {
            try await SwiftSync.sync(payload: missingReferencePayload, as: RuntimeEmployee.self, in: context)
        } catch {
            XCTFail("Expected missing referenced company to be handled without crashing, got error: \(error)")
        }

        let employees = try context.fetch(FetchDescriptor<RuntimeEmployee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertNil(employees.first?.company)
    }

    @MainActor
    func testSyncToManyNestedObjectArrayReplacesMembershipAndUpdatesExistingChild() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeTeam.self, RuntimeMember.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [[
            "id": 21,
            "name": "Inbox",
            "members": [
                ["id": 101, "full_name": "a"],
                ["id": 102, "full_name": "b"]
            ]
        ]]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeTeam.self, in: context)

        var teams = try context.fetch(FetchDescriptor<RuntimeTeam>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(Set(teams[0].members.map(\.id)), Set([101, 102]))

        let payloadB: [Any] = [[
            "id": 21,
            "name": "Inbox",
            "members": [
                ["id": 102, "full_name": "b2"],
                ["id": 103, "full_name": "c"]
            ]
        ]]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeTeam.self, in: context)

        teams = try context.fetch(FetchDescriptor<RuntimeTeam>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(Set(teams[0].members.map(\.id)), Set([102, 103]))
        XCTAssertFalse(Set(teams[0].members.map(\.id)).contains(101))

        let allMembers = try context.fetch(FetchDescriptor<RuntimeMember>())
        XCTAssertEqual(allMembers.filter { $0.id == 102 }.count, 1)
        XCTAssertEqual(allMembers.first(where: { $0.id == 102 })?.fullName, "b2")
    }

    @MainActor
    func testSyncToManyByIDsReplacesMembershipExactly() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUserWithNotes.self, RuntimeNote.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 0, "text": "n0"],
                ["id": 1, "text": "n1"],
                ["id": 2, "text": "n2"]
            ],
            as: RuntimeNote.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "U"]],
            as: RuntimeUserWithNotes.self,
            in: context
        )

        let payloadA: [Any] = [[
            "id": 10,
            "name": "U",
            "notes_ids": [0, 1]
        ]]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeUserWithNotes.self, in: context)

        var users = try context.fetch(FetchDescriptor<RuntimeUserWithNotes>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(Set(users[0].notes.map(\.id)), Set([0, 1]))

        let payloadB: [Any] = [[
            "id": 10,
            "name": "U",
            "notes_ids": [1, 2]
        ]]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeUserWithNotes.self, in: context)

        users = try context.fetch(FetchDescriptor<RuntimeUserWithNotes>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(Set(users[0].notes.map(\.id)), Set([1, 2]))
        XCTAssertFalse(Set(users[0].notes.map(\.id)).contains(0))
    }

    @MainActor
    func testSyncToManyByIDsIsIdempotentForRepeatedPayload() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUserWithNotes.self, RuntimeNote.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "n1"],
                ["id": 2, "text": "n2"]
            ],
            as: RuntimeNote.self,
            in: context
        )
        try await SwiftSync.sync(
            payload: [["id": 10, "name": "U"]],
            as: RuntimeUserWithNotes.self,
            in: context
        )

        let payloadB: [Any] = [[
            "id": 10,
            "name": "U",
            "notes_ids": [1, 2]
        ]]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeUserWithNotes.self, in: context)
        try await SwiftSync.sync(payload: payloadB, as: RuntimeUserWithNotes.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeUserWithNotes>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(Set(users[0].notes.map(\.id)), Set([1, 2]))

        let notes = try context.fetch(FetchDescriptor<RuntimeNote>())
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(Set(notes.map(\.id)), Set([1, 2]))
    }

    @MainActor
    func testSyncManyToManyObjectsAndIDsProduceEquivalentFinalGraph() async throws {
        let objectGraph = try await runManyToManyObjectsScenario()
        let idsGraph = try await runManyToManyIDsScenario()

        XCTAssertEqual(objectGraph, idsGraph)
        XCTAssertEqual(objectGraph[1], Set([2, 4]))
        XCTAssertEqual(objectGraph[2], Set([3]))
    }

    @MainActor
    func testSyncManyToManyObjectsAndIDsHaveEquivalentAddRemoveOutcomes() async throws {
        let objectGraph = try await runManyToManyObjectsScenario()
        let idsGraph = try await runManyToManyIDsScenario()

        // No duplicate join edges in either graph.
        XCTAssertEqual(objectGraph[1]?.count, 2)
        XCTAssertEqual(objectGraph[2]?.count, 1)
        XCTAssertEqual(idsGraph[1]?.count, 2)
        XCTAssertEqual(idsGraph[2]?.count, 1)

        // Same add/remove outcomes after update payload.
        XCTAssertFalse(objectGraph[1]?.contains(1) ?? true)
        XCTAssertFalse(idsGraph[1]?.contains(1) ?? true)
        XCTAssertTrue(objectGraph[1]?.contains(4) ?? false)
        XCTAssertTrue(idsGraph[1]?.contains(4) ?? false)
    }

    @MainActor
    private func runManyToManyObjectsScenario() async throws -> [Int: Set<Int>] {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUserTagsByObjects.self, RuntimeTag.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [
            [
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 1, "name": "t1"],
                    ["id": 2, "name": "t2"]
                ]
            ],
            [
                "id": 2,
                "name": "U2",
                "tags": [
                    ["id": 2, "name": "t2"],
                    ["id": 3, "name": "t3"]
                ]
            ]
        ]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeUserTagsByObjects.self, in: context)

        let payloadB: [Any] = [
            [
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 2, "name": "t2"],
                    ["id": 4, "name": "t4"]
                ]
            ],
            [
                "id": 2,
                "name": "U2",
                "tags": [
                    ["id": 3, "name": "t3"]
                ]
            ]
        ]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeUserTagsByObjects.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeUserTagsByObjects>())
        return Dictionary(uniqueKeysWithValues: users.map { ($0.id, Set($0.tags.map(\.id))) })
    }

    @MainActor
    private func runManyToManyIDsScenario() async throws -> [Int: Set<Int>] {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUserTagsByIDs.self, RuntimeTag.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "name": "t1"],
                ["id": 2, "name": "t2"],
                ["id": 3, "name": "t3"],
                ["id": 4, "name": "t4"]
            ],
            as: RuntimeTag.self,
            in: context
        )

        let payloadA: [Any] = [
            ["id": 1, "name": "U1", "tags_ids": [1, 2]],
            ["id": 2, "name": "U2", "tags_ids": [2, 3]]
        ]
        try await SwiftSync.sync(payload: payloadA, as: RuntimeUserTagsByIDs.self, in: context)

        let payloadB: [Any] = [
            ["id": 1, "name": "U1", "tags_ids": [2, 4]],
            ["id": 2, "name": "U2", "tags_ids": [3]]
        ]
        try await SwiftSync.sync(payload: payloadB, as: RuntimeUserTagsByIDs.self, in: context)

        let users = try context.fetch(FetchDescriptor<RuntimeUserTagsByIDs>())
        return Dictionary(uniqueKeysWithValues: users.map { ($0.id, Set($0.tags.map(\.id))) })
    }

}
