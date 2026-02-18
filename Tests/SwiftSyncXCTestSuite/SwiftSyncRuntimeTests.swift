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
}
