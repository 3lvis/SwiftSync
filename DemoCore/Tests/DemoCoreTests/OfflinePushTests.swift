import SwiftData
import SwiftSync
import XCTest

@testable import DemoCore

final class OfflinePushTests: XCTestCase {

    @MainActor
    func testOfflineCreateThenPushStampsRemoteIDAndReachesBackend() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)
        XCTAssertEqual(engine.pendingChangeCount, 0)

        let body = try createBody(
            from: DemoSeedData.SeedIDs.Tasks.sessionTimeout,
            newID: "OFFLINE-CREATE-1",
            in: syncContainer
        )

        engine.isOffline = true
        try await engine.createTask(body: body, projectID: projectID)

        let local = try XCTUnwrap(fetchTask(id: "OFFLINE-CREATE-1", in: syncContainer.mainContext))
        XCTAssertNil(local.syncRemoteID, "an offline-created row is pending until pushed")
        XCTAssertEqual(engine.pendingChangeCount, 1)

        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let summary = try XCTUnwrap(pushResult)

        XCTAssertEqual(summary.insertedCount, 1)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(engine.pendingChangeCount, 0)

        let synced = try XCTUnwrap(fetchTask(id: "OFFLINE-CREATE-1", in: syncContainer.mainContext))
        let remoteID = try XCTUnwrap(synced.syncRemoteID, "push stamps the server-minted remote id")
        XCTAssertNotEqual(remoteID, "OFFLINE-CREATE-1", "the server mints its own id, distinct from localId")
        XCTAssertTrue(remoteID.hasPrefix("srv-"))
        let backendDetail = try await apiClient.getTaskDetail(taskID: "OFFLINE-CREATE-1")
        XCTAssertNotNil(backendDetail, "the row reached the backend, keyed by its localId")
    }

    @MainActor
    func testOfflineDeleteThenPushHardDeletesLocallyAndOnBackend() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        engine.isOffline = true
        try await engine.deleteTask(taskID: taskID, projectID: projectID)

        let tombstone = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(tombstone.isLocallyDeleted, true, "offline delete is a soft delete until pushed")
        XCTAssertEqual(engine.pendingChangeCount, 1)

        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let summary = try XCTUnwrap(pushResult)

        XCTAssertEqual(summary.deletedCount, 1)
        XCTAssertTrue(summary.failures.isEmpty)
        let remaining = try fetchTask(id: taskID, in: syncContainer.mainContext)
        XCTAssertNil(remaining, "confirmed delete is hard-deleted")
        let detail = try await apiClient.getTaskDetail(taskID: taskID)
        XCTAssertNil(detail)
    }

    @MainActor
    func testPushWhileOfflineIsANoOp() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)

        let body = try createBody(
            from: DemoSeedData.SeedIDs.Tasks.sessionTimeout,
            newID: "OFFLINE-NOOP-1",
            in: syncContainer
        )

        engine.isOffline = true
        try await engine.createTask(body: body, projectID: projectID)
        XCTAssertEqual(engine.pendingChangeCount, 1)

        // Still offline: a push must not reach the server.
        let result = try await engine.pushPendingChanges()
        XCTAssertNil(result, "push is unavailable while offline")
        XCTAssertEqual(engine.pendingChangeCount, 1, "the pending change survives")
        let backendDetail = try await apiClient.getTaskDetail(taskID: "OFFLINE-NOOP-1")
        XCTAssertNil(backendDetail, "nothing was uploaded while offline")
    }

    @MainActor
    private func createBody(from templateID: String, newID: String, in syncContainer: SyncContainer) throws
        -> DemoSyncPayload
    {
        let template = try XCTUnwrap(fetchTask(id: templateID, in: syncContainer.mainContext))
        var dictionary = syncContainer.export(template)
        dictionary["id"] = newID
        dictionary["title"] = "Offline task"
        dictionary.removeValue(forKey: "items")
        return try DemoSyncPayload(dictionary: dictionary)
    }

    @MainActor
    private func makeSyncContainer() throws -> SyncContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try SyncContainer(
            for: Project.self,
            User.self,
            Task.self,
            Item.self,
            TaskStateOption.self,
            configurations: configuration
        )
    }

    @MainActor
    private func fetchTask(id: String, in context: ModelContext) throws -> Task? {
        try context.fetch(FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })).first
    }
}
