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
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext, options _: SyncOptions) async throws -> Bool {
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

        if payload.contains("members"), let memberPayloads: [[String: Any]] = payload.value(for: "members") {
            var desiredMembers: [RuntimeMember] = []
            for memberPayload in memberPayloads {
                desiredMembers.append(try upsertMember(from: memberPayload, in: context))
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
    func testSyncThrowsOnMissingIdentity() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [["full_name": "No ID"]]

        do {
            try await SwiftSync.sync(payload: payload, as: RuntimeUser.self, in: context)
            XCTFail("Expected missingIdentity error")
        } catch let error as SyncError {
            guard case .missingIdentity = error else {
                XCTFail("Unexpected SyncError: \(error)")
                return
            }
        }
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

}
