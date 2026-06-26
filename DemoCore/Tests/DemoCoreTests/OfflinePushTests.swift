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
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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

        XCTAssertNotNil(
            try fetchTask(id: "OFFLINE-CREATE-1", in: syncContainer.mainContext),
            "an offline-created row exists locally")
        XCTAssertEqual(engine.pendingChangeCount, 1, "and is pending until pushed")

        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let failures = try XCTUnwrap(pushResult)

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(engine.pendingChangeCount, 0)

        XCTAssertNotNil(
            try fetchTask(id: "OFFLINE-CREATE-1", in: syncContainer.mainContext), "the row remains, now synced")
        let backendDetail = try await apiClient.getTaskDetail(taskID: "OFFLINE-CREATE-1")
        XCTAssertNotNil(backendDetail, "the row reached the backend, keyed by its id")
    }

    @MainActor
    func testOnlineCreateTaskPersistsLocallyAndReachesBackend() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)

        let body = try createBody(
            from: DemoSeedData.SeedIDs.Tasks.sessionTimeout, newID: "ONLINE-CREATE-1", in: syncContainer)
        try await engine.createTask(body: body, projectID: projectID)

        XCTAssertNotNil(
            try fetchTask(id: "ONLINE-CREATE-1", in: syncContainer.mainContext), "created locally")
        XCTAssertEqual(engine.pendingChangeCount, 0, "an online create syncs immediately, not pending")
        let backendDetail = try await apiClient.getTaskDetail(taskID: "ONLINE-CREATE-1")
        XCTAssertNotNil(backendDetail, "the create reached the backend")
    }

    @MainActor
    func testOnlineDeleteTaskRemovesLocallyAndOnBackend() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.securityPolicyPatch
        try await engine.syncProjectTasks(projectID: projectID)
        XCTAssertNotNil(try fetchTask(id: taskID, in: syncContainer.mainContext))

        try await engine.deleteTask(taskID: taskID, projectID: projectID)

        XCTAssertNil(
            try fetchTask(id: taskID, in: syncContainer.mainContext), "removed locally after an online delete")
        XCTAssertEqual(engine.pendingChangeCount, 0)
        let backendDetail = try await apiClient.getTaskDetail(taskID: taskID)
        XCTAssertNil(backendDetail, "removed on the backend")
    }

    @MainActor
    func testUpdateTaskItemsAddRenameDelete() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.qaItemList
        try await engine.syncProjectTasks(projectID: projectID)
        try await engine.syncTaskDetail(taskID: taskID)

        let task = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        var body = syncContainer.export(task)
        var items = try XCTUnwrap(body["items"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(items.count, 2, "the seeded task has items to edit")

        items[0]["title"] = "Renamed item"  // rename the first
        let removed = items.remove(at: 1)  // delete the second
        let removedTitle = try XCTUnwrap(removed["title"] as? String)
        var added = items[0]  // clone the exported shape, then make it a new item
        added["id"] = "ADDED-ITEM-1"
        added["title"] = "Added item"
        items.append(added)
        body["items"] = items

        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: body))

        let updated = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let titles = updated.items.map(\.title)
        XCTAssertTrue(titles.contains("Renamed item"), "rename applied")
        XCTAssertTrue(titles.contains("Added item"), "add applied")
        XCTAssertFalse(titles.contains(removedTitle), "delete applied")
    }

    @MainActor
    func testOfflineDeleteThenPushHardDeletesLocallyAndOnBackend() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        engine.isOffline = true
        try await engine.deleteTask(taskID: taskID, projectID: projectID)

        XCTAssertNil(
            try fetchTask(id: taskID, in: syncContainer.mainContext),
            "offline delete hard-deletes locally at once; the pending deletion lives in store history")
        XCTAssertEqual(engine.pendingChangeCount, 1)

        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let failures = try XCTUnwrap(pushResult)

        XCTAssertTrue(failures.isEmpty)
        let remaining = try fetchTask(id: taskID, in: syncContainer.mainContext)
        XCTAssertNil(remaining, "confirmed delete is hard-deleted")
        let detail = try await apiClient.getTaskDetail(taskID: taskID)
        XCTAssertNil(detail)
    }

    @MainActor
    func testRejectedPushPersistsFailureReasonOnTheRow() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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
        let failures = try XCTUnwrap(pushResult)
        XCTAssertEqual(failures.count, 1)

        let failed = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let reason = try XCTUnwrap(
            failed.syncFailureReason, "the engine annotates the row from the bubbled failure")
        XCTAssertTrue(reason.contains("80 characters"), "the failure carries the server's reason: \(reason)")

        // A rejected row stays pending in the queue (pure-bubble), but it must read as *failed*, not
        // *pending* — otherwise the status bar double-counts the same task as "1 pending, 1 failed".
        XCTAssertEqual(engine.failedChangeCount, 1)
        XCTAssertEqual(engine.pendingChangeCount, 0, "a failed row is not also counted as pending")
    }

    @MainActor
    func testDiscardFailedChangeRestoresServerStateAndClearsFailure() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let id = "FAILED-INSERT-1"
        try await engine.syncProjectTasks(projectID: projectID)

        // Offline create with an over-long title → the insert is rejected on push.
        engine.isOffline = true
        let template = try XCTUnwrap(
            fetchTask(id: DemoSeedData.SeedIDs.Tasks.sessionTimeout, in: syncContainer.mainContext))
        var createDictionary = syncContainer.export(template)
        createDictionary["id"] = id
        createDictionary["title"] = String(repeating: "A", count: 100)
        createDictionary.removeValue(forKey: "items")
        try await engine.createTask(
            body: try DemoSyncPayload(dictionary: createDictionary), projectID: projectID)

        engine.isOffline = false
        _ = try await engine.pushPendingChanges()
        let failed = try XCTUnwrap(fetchTask(id: id, in: syncContainer.mainContext))
        XCTAssertNotNil(failed.syncFailureReason, "the rejected insert is flagged")
        XCTAssertEqual(engine.failedChangeCount, 1, "it never reached the server")

        // Edit it to a valid title (online): a never-synced row must be re-inserted, not PUT/404'd.
        var fixDictionary = syncContainer.export(failed)
        fixDictionary["title"] = "Fixed"
        fixDictionary.removeValue(forKey: "items")
        try await engine.updateTask(
            taskID: id, projectID: projectID, body: try DemoSyncPayload(dictionary: fixDictionary))

        let fixed = try XCTUnwrap(fetchTask(id: id, in: syncContainer.mainContext))
        XCTAssertNil(fixed.syncFailureReason, "the failure is resolved")
        XCTAssertEqual(fixed.title, "Fixed")
        let backendDetail = try await apiClient.getTaskDetail(taskID: id)
        XCTAssertNotNil(backendDetail, "it now exists on the server")
    }

    @MainActor
    func testEditingAFailedSyncedRowOnlineClearsFailure() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)

        // Offline edit of an already-synced row to an over-long title → the update is rejected on push.
        engine.isOffline = true
        let synced = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(engine.pendingChangeCount, 0, "precondition: the pulled row is already synced")
        var badDictionary = syncContainer.export(synced)
        badDictionary["title"] = String(repeating: "A", count: 100)
        badDictionary.removeValue(forKey: "items")
        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: badDictionary))

        engine.isOffline = false
        _ = try await engine.pushPendingChanges()
        let failed = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertNotNil(failed.syncFailureReason, "the rejected edit is flagged")
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
        let apiClient = FakeDemoAPIClient(backend: backend, networkDelayMode: .disabled)
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
                "operation": "upsert", "type": "tasks", "id": taskID,
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
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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

    /// The whole offline reviewer journey via the path the task-form save actually uses (reviewer_ids in
    /// the `updateTask` body): it applies locally while offline — a regression guard, since `apply()`
    /// skips the `@NotExport` relationship so nothing else would reflect it — then round-trips through
    /// push so the server holds the new set, proven by a fresh pull bringing it back.
    @MainActor
    func testOfflineReviewerEditViaUpdateBodyAppliesLocallyAndSyncsOnReconnect() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-update-people-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let backend = try DemoServerSimulator(databaseURL: url, seedData: DemoSeedData.generate())
        let apiClient = FakeDemoAPIClient(backend: backend, networkDelayMode: .disabled)
        let syncContainer = try makeSyncContainer()
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)
        try await engine.syncTaskDetail(taskID: taskID)
        try await engine.syncTaskFormMetadata()  // cache the users to assign

        let task = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let newReviewers = [DemoSeedData.SeedIDs.Users.miaPatel, DemoSeedData.SeedIDs.Users.ethanLee].sorted()

        engine.isOffline = true
        var body = syncContainer.export(task)
        body["reviewer_ids"] = newReviewers
        try await engine.updateTask(
            taskID: taskID, projectID: projectID, body: try DemoSyncPayload(dictionary: body))

        let offline = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(
            offline.reviewers.map(\.id).sorted(), newReviewers,
            "an offline updateTask with reviewer_ids must apply the reviewers to the local row")

        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let failures = try XCTUnwrap(pushResult)
        XCTAssertTrue(failures.isEmpty)

        // A fresh pull (server is authoritative) brings the same reviewers back.
        try await engine.syncTaskDetail(taskID: taskID)
        let pulled = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(
            pulled.reviewers.map(\.id).sorted(), newReviewers,
            "the offline reviewer edit persisted on the server")
    }

    /// Only `Task` is marked offline, yet a `Task`↔`User` relationship edit made offline (assigning
    /// reviewers) round-trips: assigning a person is a local *Task* update — the linked `User` is
    /// pull-only and never needs to be offline. After reconnect+push the server has the new reviewers,
    /// proven by a fresh pull bringing the same set back.
    @MainActor
    func testOfflineReviewerAssignmentRoundTripsThroughPush() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-people-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let backend = try DemoServerSimulator(databaseURL: url, seedData: DemoSeedData.generate())
        let apiClient = FakeDemoAPIClient(backend: backend, networkDelayMode: .disabled)
        let syncContainer = try makeSyncContainer()
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        let taskID = DemoSeedData.SeedIDs.Tasks.sessionTimeout
        try await engine.syncProjectTasks(projectID: projectID)
        try await engine.syncTaskFormMetadata()  // ensure the users to assign are cached locally

        let newReviewers = [DemoSeedData.SeedIDs.Users.miaPatel, DemoSeedData.SeedIDs.Users.ethanLee]

        // Offline: assign people. Mutates the Task (its reviewers + updatedAt) → a pending Task update.
        engine.isOffline = true
        try await engine.replaceTaskReviewers(taskID: taskID, projectID: projectID, reviewerIDs: newReviewers)
        let offline = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(Set(offline.reviewers.map(\.id)), Set(newReviewers), "applied locally while offline")
        XCTAssertEqual(engine.pendingChangeCount, 1, "the relationship edit is a pending Task update")

        // Reconnect + push: reviewer_ids travel in the upsert and the server accepts it.
        engine.isOffline = false
        let pushResult = try await engine.pushPendingChanges()
        let failures = try XCTUnwrap(pushResult)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(engine.pendingChangeCount, 0, "the assignment was acknowledged")

        // Prove the server stored it: a fresh pull (which overwrites local reviewers from the server)
        // brings the same set back.
        try await engine.syncTaskDetail(taskID: taskID)
        let pulled = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(
            Set(pulled.reviewers.map(\.id)), Set(newReviewers),
            "the offline assignment round-tripped: pushed to the server and pulled back")
    }

    @MainActor
    func testPushWhileOfflineIsANoOp() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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

        nonisolated(unsafe) var uploadAttempted = false
        apiClient.beforeUpload = { uploadAttempted = true }

        // Still offline: the push is a no-op — it returns nil, touches no network, and leaves the change
        // pending. Proven entirely from offline state; reconnecting to read the server would race the
        // reconnect drain that the transition itself kicks off.
        let result = try await engine.pushPendingChanges()
        XCTAssertNil(result, "push is unavailable while offline")
        XCTAssertFalse(uploadAttempted, "no upload is attempted while offline")
        XCTAssertEqual(engine.pendingChangeCount, 1, "the pending change survives")
    }

    @MainActor
    func testOfflinePullServesCacheAndDoesNotReachServer() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-read-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let backend = try DemoServerSimulator(databaseURL: url, seedData: DemoSeedData.generate())
        let apiClient = FakeDemoAPIClient(backend: backend, networkDelayMode: .disabled)
        let syncContainer = try makeSyncContainer()
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)
        let onlineCount = try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).count
        XCTAssertGreaterThan(onlineCount, 0)

        // A task appears on the server that this client has never seen.
        _ = try backend.upload(operations: [
            [
                "operation": "upsert", "type": "tasks", "id": "SERVER-ONLY-1",
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
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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
        let failures = try XCTUnwrap(pushResult)
        XCTAssertEqual(failures.count, 1)
        let failed = try XCTUnwrap(fetchTask(id: "OFFLINE-REJECT-1", in: syncContainer.mainContext))
        XCTAssertNotNil(failed.syncFailureReason, "the rejected create is flagged")

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
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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

        // The push rejects the edit, so the server still holds the pre-edit title.
        try await engine.syncProjectTasks(projectID: projectID)

        let row = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(row.title, invalidTitle, "the failed local edit must not be clobbered by the pull")
        XCTAssertNotNil(row.syncFailureReason, "it stays flagged for the user to resolve")
    }

    @MainActor
    func testNewerServerVersionOverwritesPollutedLocalEdit() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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

        try await engine.syncProjectTasks(projectID: projectID)

        let row = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(
            row.title, serverTitle, "a newer server version overwrites even a polluted local edit")
    }

    @MainActor
    func testPollutedRowDoesNotBlockSiblingRefresh() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
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

        let siblingTitle = "server-updated sibling"
        let siblingDetail = try await apiClient.getTaskDetail(taskID: siblingID)
        let siblingBody = try mutating(try XCTUnwrap(siblingDetail)) { $0["title"] = siblingTitle }
        _ = try await apiClient.updateTask(taskID: siblingID, body: siblingBody)

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

// Test-only dict bridge over the real JSON-`Data` upload wire (overloads by parameter type).
extension DemoServerSimulator {
    @discardableResult
    func upload(operations: [[String: Any]]) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: upload(operations: JSONSerialization.data(withJSONObject: operations)))
            as! [String: Any]
    }
}
