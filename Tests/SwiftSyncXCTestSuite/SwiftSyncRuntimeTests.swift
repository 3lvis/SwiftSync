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

}
