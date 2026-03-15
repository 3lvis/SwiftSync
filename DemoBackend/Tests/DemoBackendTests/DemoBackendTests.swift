import Foundation
import XCTest
@testable import DemoBackend

// Stable UUID constants for the test fixture — deterministic across runs.
private let projectID = "A1B2C3D4-0000-0000-0000-000000000001"
private let userID    = "A1B2C3D4-0000-0000-0000-000000000002"
private let taskID    = "A1B2C3D4-0000-0000-0000-000000000003"

final class DemoBackendTests: XCTestCase {
    func testSQLiteBackendSeedsAndServesReadEndpoints() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let projects = try backend.getProjectsPayload()
        let users = try backend.getUsersPayload()
        let taskStates = try backend.getTaskStateOptionsPayload()
        let projectTasks = try backend.getProjectTasksPayload(projectID: projectID)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(taskStates.count, 3)
        XCTAssertEqual(projectTasks.count, 1)

        XCTAssertNotNil(projects.first?["created_at"])
        XCTAssertNotNil(projects.first?["updated_at"])
        XCTAssertNotNil(users.first?["created_at"])
        XCTAssertNotNil(users.first?["updated_at"])
        XCTAssertNotNil(taskStates.first?["created_at"])
        XCTAssertNotNil(projectTasks.first?["created_at"])
        XCTAssertNotNil(projectTasks.first?["updated_at"])

        XCTAssertNil(users.first?["role"])
        XCTAssertNil(users.first?["avatar_seed"])
        XCTAssertNil(projectTasks.first?["due_date"])
        XCTAssertEqual(projectTasks.first?["reviewer_ids"] as? [String], [userID])
        XCTAssertEqual(projectTasks.first?["author_id"] as? String, userID)
        XCTAssertEqual(projectTasks.first?["watcher_ids"] as? [String], [userID])
        XCTAssertEqual(items(in: projectTasks.first).count, 2)
        XCTAssertEqual(
            items(in: projectTasks.first).map { $0["title"] as? String },
            ["Gather requirements", "Draft implementation plan"]
        )
        XCTAssertEqual(stateID(in: projectTasks.first), "todo")
        XCTAssertEqual(stateLabel(in: projectTasks.first), "To Do")
        XCTAssertNotNil(projectTasks.first?["description"])
        XCTAssertEqual(taskStates.map { $0["id"] as? String }, ["todo", "inProgress", "done"])
        XCTAssertEqual(taskStates.map { ($0["label"] as? String) ?? "" }, ["To Do", "In Progress", "Done"])
    }

    func testSQLiteBackendSeedEntityIDsAreUUIDs() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let seed = DemoSeedData.generate()
        let backend = try DemoServerSimulator(databaseURL: url, seedData: seed)

        let projects = try backend.getProjectsPayload()
        let users = try backend.getUsersPayload()
        let tasks = try backend.getProjectTasksPayload(projectID: seed.projects[0].id)
        let firstTaskID = tasks.first?["id"] as? String
        let detail = try backend.getTaskDetailPayload(taskID: firstTaskID ?? "")
        let taskItems = items(in: detail)

        for project in projects {
            let id = project["id"] as? String ?? ""
            XCTAssertNotNil(UUID(uuidString: id), "project id '\(id)' is not a UUID")
        }
        for user in users {
            let id = user["id"] as? String ?? ""
            XCTAssertNotNil(UUID(uuidString: id), "user id '\(id)' is not a UUID")
        }
        for task in tasks {
            let id = task["id"] as? String ?? ""
            XCTAssertNotNil(UUID(uuidString: id), "task id '\(id)' is not a UUID")
        }
        for item in taskItems {
            let id = item["id"] as? String ?? ""
            XCTAssertNotNil(UUID(uuidString: id), "item id '\(id)' is not a UUID")
        }
        XCTAssertFalse(taskItems.isEmpty)
    }

    func testCreateTaskIDIsUUID() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newID = UUID().uuidString
        let now = iso8601(Date())
        let body: [String: Any] = [
            "id": newID,
            "project_id": projectID,
            "title": "UUID id test",
            "description": "Check generated id",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now
        ]
        let created = try backend.createTask(body: body)

        XCTAssertEqual(created["id"] as? String, newID)
        XCTAssertNotNil(UUID(uuidString: newID), "task id '\(newID)' is not a UUID")
    }

    func testSQLiteBackendPatchTaskStateAndAssigneeReviewerAndRelationships() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let patchedState = try backend.patchTaskState(taskID: taskID, state: "done")
        XCTAssertEqual(stateID(in: patchedState), "done")
        XCTAssertEqual(stateLabel(in: patchedState), "Done")

        let clearedAssignee = try backend.patchTaskAssignee(taskID: taskID, assigneeID: nil)
        XCTAssertTrue((clearedAssignee?["assignee_id"] is NSNull))

        let reassigned = try backend.patchTaskAssignee(taskID: taskID, assigneeID: userID)
        XCTAssertEqual(reassigned?["assignee_id"] as? String, userID)

        let clearedReviewers = try backend.replaceTaskReviewers(taskID: taskID, reviewerIDs: [])
        XCTAssertEqual(clearedReviewers?["reviewer_ids"] as? [String], [])

        let reReviewed = try backend.replaceTaskReviewers(taskID: taskID, reviewerIDs: [userID])
        XCTAssertEqual(reReviewed?["reviewer_ids"] as? [String], [userID])

        let rewatched = try backend.replaceTaskWatchers(taskID: taskID, watcherIDs: [userID])
        XCTAssertEqual(rewatched?["watcher_ids"] as? [String], [userID])

        let clearedWatchers = try backend.replaceTaskWatchers(taskID: taskID, watcherIDs: [])
        XCTAssertEqual(clearedWatchers?["watcher_ids"] as? [String], [])
    }

    func testCreateTaskFromBodyDict() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newID = UUID().uuidString
        let createdAtString = iso8601(Date(timeIntervalSince1970: 1_700_100_000))
        let updatedAtString = iso8601(Date(timeIntervalSince1970: 1_700_100_001))

        let body: [String: Any] = [
            "id": newID,
            "project_id": projectID,
            "title": "New task from body",
            "description": "Body description",
            "state": ["id": "inProgress"],
            "assignee_id": userID,
            "author_id": userID,
            "created_at": createdAtString,
            "updated_at": updatedAtString
        ]

        let created = try backend.createTask(body: body)

        // id round-trips exactly
        XCTAssertEqual(created["id"] as? String, newID)
        XCTAssertEqual(created["project_id"] as? String, projectID)
        XCTAssertEqual(created["assignee_id"] as? String, userID)
        XCTAssertEqual(created["author_id"] as? String, userID)
        XCTAssertEqual(created["title"] as? String, "New task from body")
        XCTAssertEqual(created["description"] as? String, "Body description")
        XCTAssertEqual(stateID(in: created), "inProgress")
        XCTAssertEqual(stateLabel(in: created), "In Progress")
        XCTAssertEqual(created["reviewer_ids"] as? [String], [])
        XCTAssertEqual(created["watcher_ids"] as? [String], [])
        // timestamps round-trip
        XCTAssertEqual(created["created_at"] as? String, createdAtString)
        XCTAssertEqual(created["updated_at"] as? String, updatedAtString)
    }

    func testCreateTaskFromBodyDictNilAssignee() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let now = iso8601(Date())
        let body: [String: Any] = [
            "id": UUID().uuidString,
            "project_id": projectID,
            "title": "Unassigned task",
            "description": "No one yet",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now
        ]

        let created = try backend.createTask(body: body)
        XCTAssertTrue(created["assignee_id"] is NSNull || created["assignee_id"] == nil)
    }

    func testCreateTaskFromBodyDictValidation() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let now = iso8601(Date())
        let base: [String: Any] = [
            "id": UUID().uuidString,
            "project_id": projectID,
            "title": "Valid title",
            "description": "Valid desc",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now
        ]

        // missing id
        var missingID = base
        missingID.removeValue(forKey: "id")
        XCTAssertThrowsError(try backend.createTask(body: missingID))

        // missing project_id
        var missingProject = base
        missingProject.removeValue(forKey: "project_id")
        XCTAssertThrowsError(try backend.createTask(body: missingProject))

        // unknown project_id
        var badProject = base
        badProject["project_id"] = "00000000-0000-0000-0000-000000000000"
        XCTAssertThrowsError(try backend.createTask(body: badProject))

        // missing title
        var missingTitle = base
        missingTitle.removeValue(forKey: "title")
        XCTAssertThrowsError(try backend.createTask(body: missingTitle))

        // empty title
        var emptyTitle = base
        emptyTitle["title"] = "   "
        XCTAssertThrowsError(try backend.createTask(body: emptyTitle))

        // missing author_id
        var missingAuthor = base
        missingAuthor.removeValue(forKey: "author_id")
        XCTAssertThrowsError(try backend.createTask(body: missingAuthor))

        // unknown author_id
        var badAuthor = base
        badAuthor["author_id"] = "00000000-0000-0000-0000-000000000000"
        XCTAssertThrowsError(try backend.createTask(body: badAuthor))

        // invalid state value
        var badState = base
        badState["state"] = ["id": "flying"]
        XCTAssertThrowsError(try backend.createTask(body: badState))

        // missing state dict
        var noState = base
        noState.removeValue(forKey: "state")
        XCTAssertThrowsError(try backend.createTask(body: noState))

        // missing created_at
        var missingCreatedAt = base
        missingCreatedAt.removeValue(forKey: "created_at")
        XCTAssertThrowsError(try backend.createTask(body: missingCreatedAt))

        // missing updated_at
        var missingUpdatedAt = base
        missingUpdatedAt.removeValue(forKey: "updated_at")
        XCTAssertThrowsError(try backend.createTask(body: missingUpdatedAt))

        // duplicate id
        var firstBody = base
        let sharedID = UUID().uuidString
        firstBody["id"] = sharedID
        _ = try backend.createTask(body: firstBody)
        var duplicateBody = base
        duplicateBody["id"] = sharedID
        XCTAssertThrowsError(try backend.createTask(body: duplicateBody))
    }

    func testCreateTaskFromBodyDictWithItemsEmbedsAndReturnsItems() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newTaskID = UUID().uuidString
        let now = iso8601(Date())
        let body: [String: Any] = [
            "id": newTaskID,
            "project_id": projectID,
            "title": "Task with items",
            "description": "Has child items",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now,
            "items": [
                ["id": "item-2", "title": "Second", "position": 1],
                ["id": "item-1", "title": "First", "position": 0]
            ]
        ]

        let created = try backend.createTask(body: body)
        let createdItems = items(in: created)
        XCTAssertEqual(createdItems.count, 2)
        XCTAssertEqual(createdItems.map { $0["id"] as? String }, ["item-1", "item-2"])
        XCTAssertEqual(createdItems.map { $0["title"] as? String }, ["First", "Second"])
        XCTAssertTrue(createdItems.allSatisfy { $0["done"] == nil })
        XCTAssertEqual(createdItems.map { $0["position"] as? Int }, [0, 1])
        XCTAssertEqual(createdItems.map { $0["task_id"] as? String }, [newTaskID, newTaskID])

        let detail = try backend.getTaskDetailPayload(taskID: newTaskID)
        let detailItems = items(in: detail)
        XCTAssertEqual(detailItems.count, 2)
        XCTAssertEqual(detailItems.map { $0["id"] as? String }, ["item-1", "item-2"])
    }

    func testUpdateTaskFromBodyDictItemsKeyPresentReplacesItems() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newTaskID = UUID().uuidString
        let now = iso8601(Date())
        _ = try backend.createTask(body: [
            "id": newTaskID,
            "project_id": projectID,
            "title": "Replaceable items",
            "description": "Initial",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now,
            "items": [
                ["id": "initial-item", "title": "Initial", "position": 0]
            ]
        ])

        let updated = try backend.updateTask(taskID: newTaskID, body: [
            "id": newTaskID,
            "title": "Replaceable items",
            "description": "Updated",
            "state": ["id": "inProgress"],
            "items": [
                ["id": "item-a", "title": "A", "position": 2],
                ["id": "item-b", "title": "B", "position": 1]
            ]
        ])

        let updatedItems = items(in: updated)
        XCTAssertEqual(updatedItems.count, 2)
        XCTAssertEqual(updatedItems.map { $0["id"] as? String }, ["item-b", "item-a"])
        XCTAssertTrue(updatedItems.allSatisfy { $0["done"] == nil })
        XCTAssertFalse(updatedItems.contains { ($0["id"] as? String) == "initial-item" })
    }

    func testUpdateTaskFromBodyDictItemsKeyAbsentPreservesItems() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newTaskID = UUID().uuidString
        let now = iso8601(Date())
        _ = try backend.createTask(body: [
            "id": newTaskID,
            "project_id": projectID,
            "title": "Preserved items",
            "description": "Initial",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now,
            "items": [
                ["id": "keep-item", "title": "Keep", "position": 0]
            ]
        ])

        let updated = try backend.updateTask(taskID: newTaskID, body: [
            "id": newTaskID,
            "title": "Preserved items",
            "description": "Changed description only",
            "state": ["id": "done"]
        ])

        let updatedItems = items(in: updated)
        XCTAssertEqual(updatedItems.count, 1)
        XCTAssertEqual(updatedItems.first?["id"] as? String, "keep-item")
        XCTAssertEqual(updatedItems.first?["title"] as? String, "Keep")
    }

    func testUpdateTaskFromBodyDictItemsCanReorderWithIDAndPositionOnly() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newTaskID = UUID().uuidString
        let now = iso8601(Date())
        _ = try backend.createTask(body: [
            "id": newTaskID,
            "project_id": projectID,
            "title": "Reorder-only items",
            "description": "Initial",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now,
            "items": [
                ["id": "item-a", "title": "First", "position": 0],
                ["id": "item-b", "title": "Second", "position": 1]
            ]
        ])

        let updated = try backend.updateTask(taskID: newTaskID, body: [
            "id": newTaskID,
            "title": "Reorder-only items",
            "description": "Initial",
            "state": ["id": "todo"],
            "items": [
                ["id": "item-b", "position": 0],
                ["id": "item-a", "position": 1]
            ]
        ])

        let reorderedItems = items(in: updated)
        XCTAssertEqual(reorderedItems.map { $0["id"] as? String }, ["item-b", "item-a"])
        XCTAssertEqual(reorderedItems.map { $0["title"] as? String }, ["Second", "First"])
    }

    func testUpdateTaskFromBodyDictItemsReorderPersistsInDetailAndProjectPayloads() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newTaskID = UUID().uuidString
        let now = iso8601(Date())
        _ = try backend.createTask(body: [
            "id": newTaskID,
            "project_id": projectID,
            "title": "Persisted reorder",
            "description": "Initial",
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now,
            "items": [
                ["id": "item-a", "title": "First", "position": 0],
                ["id": "item-b", "title": "Second", "position": 1]
            ]
        ])

        _ = try backend.updateTask(taskID: newTaskID, body: [
            "id": newTaskID,
            "title": "Persisted reorder",
            "description": "Initial",
            "state": ["id": "todo"],
            "items": [
                ["id": "item-b", "position": 0],
                ["id": "item-a", "position": 1]
            ]
        ])

        let detail = try backend.getTaskDetailPayload(taskID: newTaskID)
        XCTAssertEqual(items(in: detail).map { $0["id"] as? String }, ["item-b", "item-a"])

        let projectTasks = try backend.getProjectTasksPayload(projectID: projectID)
        let persistedTask = projectTasks.first { ($0["id"] as? String) == newTaskID }
        XCTAssertEqual(items(in: persistedTask).map { $0["id"] as? String }, ["item-b", "item-a"])
    }

    func testSQLiteBackendCreateAndDeleteTaskUpdatesProjectSlice() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let newID = UUID().uuidString
        let now = iso8601(Date())
        let body: [String: Any] = [
            "id": newID,
            "project_id": projectID,
            "title": "New task",
            "description": "Server description",
            "state": ["id": "todo"],
            "assignee_id": userID,
            "author_id": userID,
            "created_at": now,
            "updated_at": now
        ]

        let created = try backend.createTask(body: body)

        XCTAssertEqual(created["id"] as? String, newID)
        XCTAssertEqual(created["project_id"] as? String, projectID)
        XCTAssertEqual(created["assignee_id"] as? String, userID)
        XCTAssertEqual(created["reviewer_ids"] as? [String], [])
        XCTAssertEqual(created["author_id"] as? String, userID)
        XCTAssertEqual(created["watcher_ids"] as? [String], [])
        XCTAssertEqual(stateID(in: created), "todo")
        XCTAssertEqual(stateLabel(in: created), "To Do")

        let projectTasksAfterCreate = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertEqual(projectTasksAfterCreate.count, 2)
        XCTAssertTrue(projectTasksAfterCreate.contains { ($0["id"] as? String) == newID })

        try backend.deleteTask(taskID: newID)

        XCTAssertNil(try backend.getTaskDetailPayload(taskID: newID))

        let projectTasksAfterDelete = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertEqual(projectTasksAfterDelete.count, 1)
        XCTAssertEqual(projectTasksAfterDelete[0]["id"] as? String, taskID)
    }

    func testUpdateTaskFromBodyDictUpdatesAllMutableFields() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let before = try backend.getTaskDetailPayload(taskID: taskID)
        let beforeUpdatedAt = before?["updated_at"] as? String

        // Build a body that mirrors the shape SwiftSync's exportObject produces:
        // - description (not description_text) from @RemoteKey("description")
        // - state as a nested dict with id+label from @RemoteKey("state.id") / @RemoteKey("state.label")
        let body: [String: Any] = [
            "id": taskID,
            "title": "Updated title via PUT",
            "description": "Updated description via PUT",
            "state": ["id": "done", "label": "Done"],
            "assignee_id": NSNull()
        ]

        let updated = try backend.updateTask(taskID: taskID, body: body)

        XCTAssertEqual(updated["id"] as? String, taskID)
        XCTAssertEqual(updated["title"] as? String, "Updated title via PUT")
        XCTAssertEqual(updated["description"] as? String, "Updated description via PUT")
        XCTAssertEqual(stateID(in: updated), "done")
        XCTAssertEqual(stateLabel(in: updated), "Done")
        XCTAssertTrue(updated["assignee_id"] is NSNull || updated["assignee_id"] == nil,
                      "NSNull assignee_id must clear the assignee")
        // updated_at must advance
        XCTAssertNotEqual(updated["updated_at"] as? String, beforeUpdatedAt)
        // created_at must not change
        XCTAssertEqual(updated["created_at"] as? String, before?["created_at"] as? String)
    }

    func testUpdateTaskFromBodyDictAllowsClearingDescriptionToNull() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let updated = try backend.updateTask(taskID: taskID, body: [
            "id": taskID,
            "title": "Updated title via PUT",
            "description": NSNull(),
            "state": ["id": "todo", "label": "To Do"]
        ])

        XCTAssertEqual(updated["id"] as? String, taskID)
        XCTAssertTrue(updated["description"] is NSNull || updated["description"] == nil)
    }

    func testCreateTaskAllowsNullDescription() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let taskID = UUID().uuidString
        let now = iso8601(Date())
        let created = try backend.createTask(body: [
            "id": taskID,
            "project_id": projectID,
            "title": "Null description task",
            "description": NSNull(),
            "state": ["id": "todo"],
            "author_id": userID,
            "created_at": now,
            "updated_at": now
        ])

        XCTAssertEqual(created["id"] as? String, taskID)
        XCTAssertTrue(created["description"] is NSNull || created["description"] == nil)
    }

    func testUpdateTaskFromBodyDictNotFoundThrows() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let body: [String: Any] = [
            "title": "irrelevant",
            "description": "irrelevant",
            "state": ["id": "todo"]
        ]
        XCTAssertThrowsError(
            try backend.updateTask(taskID: "00000000-0000-0000-0000-000000000000", body: body)
        )
    }

    func testUpdateTaskFromBodyDictIDMismatchThrows() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let body: [String: Any] = [
            "id": "different-id",
            "title": "T",
            "description": "D",
            "state": ["id": "todo"]
        ]
        XCTAssertThrowsError(try backend.updateTask(taskID: taskID, body: body))
    }

    func testUpdateTaskFromBodyDictMissingRequiredFieldThrows() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        // missing title
        XCTAssertThrowsError(try backend.updateTask(taskID: taskID, body: [
            "description": "D", "state": ["id": "todo"]
        ]))

        // missing description
        XCTAssertThrowsError(try backend.updateTask(taskID: taskID, body: [
            "title": "T", "state": ["id": "todo"]
        ]))

        // missing state
        XCTAssertThrowsError(try backend.updateTask(taskID: taskID, body: [
            "title": "T", "description": "D"
        ]))

        // invalid state value
        XCTAssertThrowsError(try backend.updateTask(taskID: taskID, body: [
            "title": "T", "description": "D", "state": ["id": "invalid"]
        ]))
    }

    func testUpdateTaskPreservesAssigneeWhenKeyAbsent() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        // The seeded task has assigneeID = userID. Omitting assignee_id from body must preserve it.
        let body: [String: Any] = [
            "title": "No assignee key",
            "description": "Preserve existing assignee",
            "state": ["id": "todo"]
        ]
        let updated = try backend.updateTask(taskID: taskID, body: body)
        XCTAssertEqual(updated["assignee_id"] as? String, userID,
                       "Omitting assignee_id must preserve the existing assignee")
    }

    func testSQLiteBackendAmbientProjectMutationKeepsSliceValid() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(
            databaseURL: url,
            seedData: smallSeedData(),
            enableAmbientProjectMutationsOnRead: true
        )

        for _ in 1...8 {
            _ = try backend.getProjectTasksPayload(projectID: projectID)
        }

        let projectTasks = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertFalse(projectTasks.isEmpty)
        XCTAssertTrue(projectTasks.allSatisfy { ($0["project_id"] as? String) == projectID })

        for task in projectTasks {
            let state = (task["state"] as? [String: Any])?["id"] as? String
            XCTAssertTrue(["todo", "inProgress", "done"].contains(state ?? ""))
            XCTAssertNotNil((task["state"] as? [String: Any])?["label"] as? String)
            XCTAssertNotNil(task["created_at"])
        }
    }

    // MARK: - Helpers

    private func stateID(in task: [String: Any]?) -> String? {
        (task?["state"] as? [String: Any])?["id"] as? String
    }

    private func stateLabel(in task: [String: Any]?) -> String? {
        (task?["state"] as? [String: Any])?["label"] as? String
    }

    private func items(in task: [String: Any]?) -> [[String: Any]] {
        (task?["items"] as? [[String: Any]]) ?? []
    }

    private func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoBackendTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func smallSeedData() -> DemoSeedData {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return DemoSeedData(
            projects: [.init(id: projectID, name: "Project", createdAt: now, updatedAt: now)],
            users: [.init(id: userID, displayName: "User", createdAt: now, updatedAt: now)],
            tasks: [
                .init(
                    id: taskID,
                    projectID: projectID,
                    assigneeID: userID,
                    reviewerIDs: [userID],
                    authorID: userID,
                    title: "Task 1",
                    descriptionText: "Old description",
                    state: "todo",
                    watcherIDs: [userID],
                    createdAt: now,
                    updatedAt: now
                )
            ],
            items: [
                .init(
                    id: "B1B2C3D4-0000-0000-0000-000000000010",
                    taskID: taskID,
                    title: "Gather requirements",
                    position: 0,
                    createdAt: now,
                    updatedAt: now
                ),
                .init(
                    id: "B1B2C3D4-0000-0000-0000-000000000011",
                    taskID: taskID,
                    title: "Draft implementation plan",
                    position: 1,
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )
    }
}
