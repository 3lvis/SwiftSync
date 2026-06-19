import DemoBackend
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
    func testRejectedPushPersistsFailureReasonOnTheRow() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        // Offline: rename the task to an over-long title the server will reject.
        engine.isOffline = true
        let task = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        var dictionary = syncContainer.export(task)
        dictionary["title"] = String(repeating: "A", count: 100)
        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: dictionary))

        // Reconnect + push: the server rejects, and the failure is recorded on the row.
        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let summary = try XCTUnwrap(pushResult)
        XCTAssertEqual(summary.failures.count, 1)

        let failed = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let reason = try XCTUnwrap(failed.syncFailureReason, "the rejection is persisted on the row")
        XCTAssertTrue(reason.contains("80 characters"), "the failure carries the server's reason: \(reason)")
    }

    @MainActor
    func testDiscardFailedChangeRestoresServerStateAndClearsFailure() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)
        let originalTitle = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext)).title

        // Offline over-long rename → reject on push → failure recorded.
        engine.isOffline = true
        let task = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        var dictionary = syncContainer.export(task)
        dictionary["title"] = String(repeating: "A", count: 100)
        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: dictionary))
        engine.isOffline = false
        _ = try await engine.pushPendingChanges()
        XCTAssertNotNil(try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext)).syncFailureReason)

        // Discard: restores the server's title and clears the failure.
        try await engine.discardFailedChange(taskID: taskID)
        let discarded = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertNil(discarded.syncFailureReason, "discard clears the failure")
        XCTAssertEqual(discarded.title, originalTitle, "discard restores the server's version")
        XCTAssertEqual(engine.failedChangeCount, 0)
    }

    @MainActor
    func testEditingAFailedInsertReinsertsInsteadOf404() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let localID = "FAILED-INSERT-1"
        try await engine.syncProjectTasks(projectID: projectID)

        // Offline create with an over-long title → the insert is rejected on push.
        engine.isOffline = true
        let template = try XCTUnwrap(
            fetchTask(id: DemoSeedData.SeedIDs.Tasks.sessionTimeout, in: syncContainer.mainContext))
        var createDictionary = syncContainer.export(template)
        createDictionary["id"] = localID
        createDictionary["title"] = String(repeating: "A", count: 100)
        createDictionary.removeValue(forKey: "items")
        try await engine.createTask(
            body: try DemoSyncPayload(dictionary: createDictionary), projectID: projectID)

        engine.isOffline = false
        _ = try await engine.pushPendingChanges()
        let failed = try XCTUnwrap(fetchTask(id: localID, in: syncContainer.mainContext))
        XCTAssertNotNil(failed.syncFailureReason, "the rejected insert is flagged")
        XCTAssertNil(failed.syncRemoteID, "it never reached the server")

        // Edit it to a valid title (online): a never-synced row must be re-inserted, not PUT/404'd.
        var fixDictionary = syncContainer.export(failed)
        fixDictionary["title"] = "Fixed"
        fixDictionary.removeValue(forKey: "items")
        try await engine.updateTask(
            taskID: localID, projectID: projectID, body: try DemoSyncPayload(dictionary: fixDictionary))

        let fixed = try XCTUnwrap(fetchTask(id: localID, in: syncContainer.mainContext))
        XCTAssertNotNil(fixed.syncRemoteID, "the corrected task is inserted on the server")
        XCTAssertNil(fixed.syncFailureReason, "the failure is resolved")
        XCTAssertEqual(fixed.title, "Fixed")
        let backendDetail = try await apiClient.getTaskDetail(taskID: localID)
        XCTAssertNotNil(backendDetail, "it now exists on the server")
    }

    @MainActor
    func testEditingAFailedSyncedRowOnlineClearsFailure() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        // Offline edit of an already-synced row to an over-long title → the update is rejected on push.
        engine.isOffline = true
        let synced = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertNotNil(synced.syncRemoteID, "precondition: the row is already synced")
        var badDictionary = syncContainer.export(synced)
        badDictionary["title"] = String(repeating: "A", count: 100)
        badDictionary.removeValue(forKey: "items")
        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: badDictionary))

        engine.isOffline = false
        _ = try await engine.pushPendingChanges()
        let failed = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertNotNil(failed.syncFailureReason, "the rejected edit is flagged")
        XCTAssertNotNil(failed.syncRemoteID, "it is still a synced row, not a fresh insert")
        XCTAssertEqual(engine.failedChangeCount, 1)

        // Fix it with a valid title while online: the corrected save must resolve the failure.
        var fixDictionary = syncContainer.export(failed)
        fixDictionary["title"] = "Fixed online"
        fixDictionary.removeValue(forKey: "items")
        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: fixDictionary))

        let fixed = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertNil(fixed.syncFailureReason, "the failure clears once the corrected edit saves")
        XCTAssertEqual(engine.failedChangeCount, 0, "the row leaves the failures inbox")
        XCTAssertEqual(fixed.title, "Fixed online")
    }

    @MainActor
    func testConflictStaleAdoptionReflectsServerStateImmediately() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-adopt-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let backend = try DemoServerSimulator(databaseURL: url, seedData: DemoSeedData.generate())
        let apiClient = FakeDemoAPIClient(backend: backend)
        let syncContainer = try makeSyncContainer()
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        // A detail view holds the registered main-context row.
        let held = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))

        // Offline edit first (timestamp T1).
        engine.isOffline = true
        var localEdit = syncContainer.export(held)
        localEdit["title"] = "Local edit"
        localEdit.removeValue(forKey: "items")
        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: localEdit))

        // Then another client advances the server's copy (timestamp T2 > T1), so our edit loses LWW.
        let serverTitle = "Server wins \(UUID().uuidString.prefix(6))"
        var serverData = syncContainer.export(held)
        serverData["title"] = serverTitle
        serverData["updated_at"] = "2099-01-01T00:00:00.000Z"
        serverData.removeValue(forKey: "items")
        _ = try backend.upload(operations: [
            [
                "operation": "upsert", "type": "tasks", "localId": taskID,
                "updatedAt": "2099-01-01T00:00:00.000Z", "data": serverData,
            ]
        ])

        // Reconnect and push → server returns stale; the engine adopts the server's version.
        engine.isOffline = false
        _ = try await engine.pushPendingChanges()

        // The held row must show the adopted server value at once — not the stale local edit.
        XCTAssertEqual(held.title, serverTitle, "conflict resolution must reflect on the live row immediately")
    }

    @MainActor
    func testOfflineEditOfCreatedTaskUpdatesTitleAndKeepsProjectLink() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)

        engine.isOffline = true
        let createBody = try createBody(
            from: DemoSeedData.SeedIDs.Tasks.sessionTimeout, newID: "OFFLINE-EDIT-1", in: syncContainer)
        try await engine.createTask(body: createBody, projectID: projectID)

        let created = try XCTUnwrap(fetchTask(id: "OFFLINE-EDIT-1", in: syncContainer.mainContext))
        XCTAssertEqual(created.project?.id, projectID, "precondition: the created task is linked to its project")

        var editDictionary = syncContainer.export(created)
        editDictionary["title"] = "Renamed offline"
        editDictionary.removeValue(forKey: "items")
        try await engine.updateTask(
            taskID: "OFFLINE-EDIT-1", projectID: projectID,
            body: try DemoSyncPayload(dictionary: editDictionary))

        let edited = try XCTUnwrap(fetchTask(id: "OFFLINE-EDIT-1", in: syncContainer.mainContext))
        XCTAssertEqual(edited.title, "Renamed offline", "the edit updates the local row's title")
        XCTAssertEqual(edited.project?.id, projectID, "the edit must not drop the project link")
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

        // Reconnect to confirm the server never received it (the transport is unreachable offline).
        engine.isOffline = false
        let backendDetail = try await apiClient.getTaskDetail(taskID: "OFFLINE-NOOP-1")
        XCTAssertNil(backendDetail, "nothing was uploaded while offline")
    }

    @MainActor
    func testOfflinePullServesCacheAndDoesNotReachServer() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-read-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let backend = try DemoServerSimulator(databaseURL: url, seedData: DemoSeedData.generate())
        let apiClient = FakeDemoAPIClient(backend: backend)
        let syncContainer = try makeSyncContainer()
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)
        let onlineCount = try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).count
        XCTAssertGreaterThan(onlineCount, 0)

        // A task appears on the server that this client has never seen.
        _ = try backend.upload(operations: [
            [
                "operation": "upsert", "type": "tasks", "localId": "SERVER-ONLY-1",
                "updatedAt": "2026-06-16T20:00:00.000Z",
                "data": [
                    "id": "SERVER-ONLY-1",
                    "project_id": projectID, "author_id": DemoSeedData.SeedIDs.Users.avaMartinez,
                    "title": "Created on the server", "description": "x", "state": ["id": "todo"],
                    "created_at": "2026-06-16T20:00:00.000Z", "updated_at": "2026-06-16T20:00:00.000Z",
                ],
            ]
        ])

        // Offline: a pull must not reach the server — no error, and no new data.
        engine.isOffline = true
        try await engine.syncProjectTasks(projectID: projectID)
        let offlineCount = try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).count
        XCTAssertEqual(offlineCount, onlineCount, "offline pull serves the local cache, never the server")

        // Reconnect: the server task is pulled in.
        engine.isOffline = false
        try await engine.syncProjectTasks(projectID: projectID)
        let refreshedCount = try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).count
        XCTAssertEqual(refreshedCount, onlineCount + 1, "reconnecting refreshes from the server")
    }

    @MainActor
    func testRejectedOfflineCreatedTaskSurvivesProjectPull() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)

        // Offline-create a task the server will reject (too-long title); it stays a never-synced row.
        var body = try createBody(
            from: DemoSeedData.SeedIDs.Tasks.sessionTimeout, newID: "OFFLINE-REJECT-1", in: syncContainer)
        body = try mutating(body) { $0["title"] = String(repeating: "A", count: 100) }
        engine.isOffline = true
        try await engine.createTask(body: body, projectID: projectID)
        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let summary = try XCTUnwrap(pushResult)
        XCTAssertEqual(summary.failures.count, 1)
        let failed = try XCTUnwrap(fetchTask(id: "OFFLINE-REJECT-1", in: syncContainer.mainContext))
        XCTAssertNil(failed.syncRemoteID, "the rejected create never got a server id")

        // Re-pull the project's task set (as on relaunch); the server omits the never-accepted row.
        try await engine.syncProjectTasks(projectID: projectID)

        let survivor = try fetchTask(id: "OFFLINE-REJECT-1", in: syncContainer.mainContext)
        XCTAssertNotNil(
            survivor,
            "a rejected offline-created task must survive an inbound project pull, not silently vanish")
    }

    @MainActor
    func testOfflineEditSurvivesServerSideDeleteOnReconnect() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        engine.isOffline = true
        let task = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let body = try mutating(try DemoSyncPayload(dictionary: syncContainer.export(task))) {
            $0["title"] = "edited offline"
        }
        try await engine.updateTask(taskID: taskID, projectID: projectID, body: body)

        // Meanwhile the server hard-deletes that task (another client / admin removed it).
        engine.isOffline = false
        try await apiClient.deleteTask(taskID: taskID)

        // syncProjectTasks pushes before it pulls, so the pending edit is upserted (re-creating the
        // server-deleted row) and the pull then sees it present, not absent.
        try await engine.syncProjectTasks(projectID: projectID)

        let survivor = try XCTUnwrap(
            fetchTask(id: taskID, in: syncContainer.mainContext),
            "an offline edit must survive a server-side delete on reconnect, not vanish")
        XCTAssertEqual(survivor.title, "edited offline", "the local edit is preserved")
    }

    @MainActor
    func testFailedOfflineEditIsNotClobberedByProjectRefresh() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        // Offline: edit a synced task to an invalid (too-long) title the server will reject on push.
        engine.isOffline = true
        let task = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let invalidTitle = String(repeating: "A", count: 100)
        let body = try mutating(try DemoSyncPayload(dictionary: syncContainer.export(task))) {
            $0["title"] = invalidTitle
        }
        try await engine.updateTask(taskID: taskID, projectID: projectID, body: body)
        engine.isOffline = false

        // Refresh: the drain rejects the edit, so the server still holds the pre-edit title. The pull
        // must not overwrite the un-pushed local edit with that stale server version.
        try await engine.syncProjectTasks(projectID: projectID)

        let row = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(row.title, invalidTitle, "the failed local edit must not be clobbered by the pull")
        XCTAssertNotNil(row.syncFailureReason, "it stays flagged for the user to resolve")
    }

    @MainActor
    func testNewerServerVersionOverwritesPollutedLocalEdit() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        // Pollute: offline edit to an invalid (too-long) title the server rejects on push.
        engine.isOffline = true
        let task = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let invalidBody = try mutating(try DemoSyncPayload(dictionary: syncContainer.export(task))) {
            $0["title"] = String(repeating: "A", count: 100)
        }
        try await engine.updateTask(taskID: taskID, projectID: projectID, body: invalidBody)
        engine.isOffline = false
        _ = try await engine.pushPendingChanges()
        XCTAssertNotNil(
            try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext)).syncFailureReason,
            "the row is polluted (a failed local edit)")

        // Another client updates that task server-side to a newer, valid version.
        let serverTitle = "server's newer title"
        let currentDetail = try await apiClient.getTaskDetail(taskID: taskID)
        let current = try XCTUnwrap(currentDetail)
        let serverBody = try mutating(current) { $0["title"] = serverTitle }
        _ = try await apiClient.updateTask(taskID: taskID, body: serverBody)

        // Refresh: the newer server version must win and overwrite the polluted local edit (LWW).
        try await engine.syncProjectTasks(projectID: projectID)

        let row = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(
            row.title, serverTitle, "a newer server version overwrites even a polluted local edit")
    }

    @MainActor
    func testPollutedRowDoesNotBlockSiblingRefresh() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let pollutedID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        let siblingID = DemoSeedData.SeedIDs.Tasks.securityPolicyPatch
        try await engine.syncProjectTasks(projectID: projectID)

        // Pollute one task: an offline edit to an invalid title the server rejects on push.
        engine.isOffline = true
        let polluted = try XCTUnwrap(fetchTask(id: pollutedID, in: syncContainer.mainContext))
        let invalidTitle = String(repeating: "A", count: 100)
        let invalidBody = try mutating(try DemoSyncPayload(dictionary: syncContainer.export(polluted))) {
            $0["title"] = invalidTitle
        }
        try await engine.updateTask(taskID: pollutedID, projectID: projectID, body: invalidBody)
        engine.isOffline = false
        _ = try await engine.pushPendingChanges()

        // A *different* task in the same project is updated server-side.
        let siblingTitle = "server-updated sibling"
        let siblingDetail = try await apiClient.getTaskDetail(taskID: siblingID)
        let siblingBody = try mutating(try XCTUnwrap(siblingDetail)) { $0["title"] = siblingTitle }
        _ = try await apiClient.updateTask(taskID: siblingID, body: siblingBody)

        // Refresh: the polluted row's local edit is preserved (LWW), and the sibling still picks up the
        // server update — one conflicted row must not block the whole project's refresh.
        try await engine.syncProjectTasks(projectID: projectID)

        let pollutedRow = try XCTUnwrap(fetchTask(id: pollutedID, in: syncContainer.mainContext))
        let siblingRow = try XCTUnwrap(fetchTask(id: siblingID, in: syncContainer.mainContext))
        XCTAssertEqual(pollutedRow.title, invalidTitle, "the conflicted row keeps its local edit")
        XCTAssertEqual(siblingRow.title, siblingTitle, "a sibling row still refreshes — the pull isn't blocked")
    }

    private func mutating(_ body: DemoSyncPayload, _ transform: (inout [String: Any]) -> Void) throws
        -> DemoSyncPayload
    {
        var dictionary = body.toSyncPayloadDictionary()
        transform(&dictionary)
        return try DemoSyncPayload(dictionary: dictionary)
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
