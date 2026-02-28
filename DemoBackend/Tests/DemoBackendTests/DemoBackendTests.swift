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
        let userRoles = try backend.getUserRoleOptionsPayload()
        let projectTasks = try backend.getProjectTasksPayload(projectID: projectID)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(taskStates.count, 3)
        XCTAssertEqual(userRoles.count, 1)
        XCTAssertEqual(projectTasks.count, 1)

        XCTAssertEqual((users.first?["role"] as? [String: Any])?["id"] as? String, "Engineer")
        XCTAssertEqual((users.first?["role"] as? [String: Any])?["label"] as? String, "Engineer")
        XCTAssertNil(users.first?["avatar_seed"])
        XCTAssertNil(projectTasks.first?["due_date"])
        XCTAssertEqual(projectTasks.first?["reviewer_ids"] as? [String], [userID])
        XCTAssertEqual(projectTasks.first?["author_id"] as? String, userID)
        XCTAssertEqual(projectTasks.first?["watcher_ids"] as? [String], [userID])
        XCTAssertEqual(stateID(in: projectTasks.first), "todo")
        XCTAssertEqual(stateLabel(in: projectTasks.first), "To Do")
        XCTAssertNotNil(projectTasks.first?["description"])
        XCTAssertNotNil(projectTasks.first?["updated_at"])
        XCTAssertEqual(taskStates.map { $0["id"] as? String }, ["todo", "inProgress", "done"])
        XCTAssertEqual(taskStates.map { ($0["label"] as? String) ?? "" }, ["To Do", "In Progress", "Done"])
        XCTAssertEqual(userRoles.map { $0["id"] as? String }, ["Engineer"])
    }

    func testSQLiteBackendSeedEntityIDsAreUUIDs() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let seed = DemoSeedData.generate()
        let backend = try DemoServerSimulator(databaseURL: url, seedData: seed)

        let projects = try backend.getProjectsPayload()
        let users = try backend.getUsersPayload()
        let tasks = try backend.getProjectTasksPayload(projectID: seed.projects[0].id)

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
    }

    func testCreateTaskIDIsUUID() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let body: [String: Any] = [
            "project_id": projectID,
            "title": "UUID id test",
            "description": "Check generated id",
            "state": ["id": "todo"],
            "author_id": userID
        ]
        let created = try backend.createTask(body: body)

        let newID = created["id"] as? String ?? ""
        XCTAssertNotNil(UUID(uuidString: newID), "created task id '\(newID)' is not a UUID")
    }

    func testSQLiteBackendPatchTaskDescriptionPersistsAcrossReopen() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let before = try backend.getTaskDetailPayload(taskID: taskID)
        let beforeUpdatedAt = before?["updated_at"] as? String
        XCTAssertEqual(before?["description"] as? String, "Old description")

        let patched = try backend.patchTaskDescription(
            taskID: taskID,
            descriptionText: "New description from server"
        )

        XCTAssertEqual(patched?["description"] as? String, "New description from server")
        XCTAssertNotEqual(patched?["updated_at"] as? String, beforeUpdatedAt)

        let reopened = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())
        let reopenedTask = try reopened.getTaskDetailPayload(taskID: taskID)
        XCTAssertEqual(reopenedTask?["description"] as? String, "New description from server")
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

        let body: [String: Any] = [
            "project_id": projectID,
            "title": "New task from body",
            "description": "Body description",
            "state": ["id": "inProgress"],
            "assignee_id": userID,
            "author_id": userID
        ]

        let created = try backend.createTask(body: body)

        guard let newTaskID = created["id"] as? String else {
            XCTFail("Expected created task id")
            return
        }
        XCTAssertFalse(newTaskID.isEmpty)
        XCTAssertNotNil(UUID(uuidString: newTaskID), "created task id '\(newTaskID)' is not a UUID")
        XCTAssertEqual(created["project_id"] as? String, projectID)
        XCTAssertEqual(created["assignee_id"] as? String, userID)
        XCTAssertEqual(created["author_id"] as? String, userID)
        XCTAssertEqual(created["title"] as? String, "New task from body")
        XCTAssertEqual(created["description"] as? String, "Body description")
        XCTAssertEqual(stateID(in: created), "inProgress")
        XCTAssertEqual(stateLabel(in: created), "In Progress")
        XCTAssertEqual(created["reviewer_ids"] as? [String], [])
        XCTAssertEqual(created["watcher_ids"] as? [String], [])
    }

    func testCreateTaskFromBodyDictNilAssignee() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        // assignee_id absent from body → task created with no assignee
        let body: [String: Any] = [
            "project_id": projectID,
            "title": "Unassigned task",
            "description": "No one yet",
            "state": ["id": "todo"],
            "author_id": userID
        ]

        let created = try backend.createTask(body: body)
        XCTAssertTrue(created["assignee_id"] is NSNull || created["assignee_id"] == nil)
    }

    func testCreateTaskFromBodyDictValidation() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let base: [String: Any] = [
            "project_id": projectID,
            "title": "Valid title",
            "description": "Valid desc",
            "state": ["id": "todo"],
            "author_id": userID
        ]

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

        // missing state dict entirely
        var noState = base
        noState.removeValue(forKey: "state")
        XCTAssertThrowsError(try backend.createTask(body: noState))
    }

    func testSQLiteBackendCreateAndDeleteTaskUpdatesProjectSlice() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let body: [String: Any] = [
            "project_id": projectID,
            "title": "New task",
            "description": "Server description",
            "state": ["id": "todo"],
            "assignee_id": userID,
            "author_id": userID
        ]

        let created = try backend.createTask(body: body)

        guard let newTaskID = created["id"] as? String else {
            XCTFail("Expected created task id")
            return
        }
        XCTAssertEqual(created["project_id"] as? String, projectID)
        XCTAssertEqual(created["assignee_id"] as? String, userID)
        XCTAssertEqual(created["reviewer_ids"] as? [String], [])
        XCTAssertEqual(created["author_id"] as? String, userID)
        XCTAssertEqual(created["watcher_ids"] as? [String], [])
        XCTAssertEqual(stateID(in: created), "todo")
        XCTAssertEqual(stateLabel(in: created), "To Do")

        let projectTasksAfterCreate = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertEqual(projectTasksAfterCreate.count, 2)
        XCTAssertTrue(projectTasksAfterCreate.contains { ($0["id"] as? String) == newTaskID })

        try backend.deleteTask(taskID: newTaskID)

        XCTAssertNil(try backend.getTaskDetailPayload(taskID: newTaskID))

        let projectTasksAfterDelete = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertEqual(projectTasksAfterDelete.count, 1)
        XCTAssertEqual(projectTasksAfterDelete[0]["id"] as? String, taskID)
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
        }
    }

    private func stateID(in task: [String: Any]?) -> String? {
        (task?["state"] as? [String: Any])?["id"] as? String
    }

    private func stateLabel(in task: [String: Any]?) -> String? {
        (task?["state"] as? [String: Any])?["label"] as? String
    }

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoBackendTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func smallSeedData() -> DemoSeedData {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return DemoSeedData(
            projects: [.init(id: projectID, name: "Project", updatedAt: now)],
            users: [.init(id: userID, displayName: "User", role: "Engineer", updatedAt: now)],
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
                    updatedAt: now
                )
            ]
        )
    }
}
