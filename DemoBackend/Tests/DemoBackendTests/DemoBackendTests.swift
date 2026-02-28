import Foundation
import XCTest
@testable import DemoBackend

final class DemoBackendTests: XCTestCase {
    func testSQLiteBackendSeedsAndServesReadEndpoints() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let projects = try backend.getProjectsPayload()
        let users = try backend.getUsersPayload()
        let taskStates = try backend.getTaskStateOptionsPayload()
        let userRoles = try backend.getUserRoleOptionsPayload()
        let projectTasks = try backend.getProjectTasksPayload(projectID: "project-1")

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(taskStates.count, 3)
        XCTAssertEqual(userRoles.count, 1)
        XCTAssertEqual(projectTasks.count, 1)

        XCTAssertEqual((users.first?["role"] as? [String: Any])?["id"] as? String, "Engineer")
        XCTAssertEqual((users.first?["role"] as? [String: Any])?["label"] as? String, "Engineer")
        XCTAssertNil(users.first?["avatar_seed"])
        XCTAssertNil(projectTasks.first?["due_date"])
        XCTAssertEqual(projectTasks.first?["reviewer_ids"] as? [String], ["user-1"])
        XCTAssertEqual(projectTasks.first?["author_id"] as? String, "user-1")
        XCTAssertEqual(projectTasks.first?["watcher_ids"] as? [String], ["user-1"])
        XCTAssertEqual(stateID(in: projectTasks.first), "todo")
        XCTAssertEqual(stateLabel(in: projectTasks.first), "To Do")
        XCTAssertNotNil(projectTasks.first?["description"])
        XCTAssertNotNil(projectTasks.first?["updated_at"])
        XCTAssertEqual(taskStates.map { $0["id"] as? String }, ["todo", "inProgress", "done"])
        XCTAssertEqual(taskStates.map { ($0["label"] as? String) ?? "" }, ["To Do", "In Progress", "Done"])
        XCTAssertEqual(userRoles.map { $0["id"] as? String }, ["Engineer"])
    }

    func testSQLiteBackendPatchTaskDescriptionPersistsAcrossReopen() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let before = try backend.getTaskDetailPayload(taskID: "task-1")
        let beforeUpdatedAt = before?["updated_at"] as? String
        XCTAssertEqual(before?["description"] as? String, "Old description")

        let patched = try backend.patchTaskDescription(
            taskID: "task-1",
            descriptionText: "New description from server"
        )

        XCTAssertEqual(patched?["description"] as? String, "New description from server")
        XCTAssertNotEqual(patched?["updated_at"] as? String, beforeUpdatedAt)

        let reopened = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())
        let reopenedTask = try reopened.getTaskDetailPayload(taskID: "task-1")
        XCTAssertEqual(reopenedTask?["description"] as? String, "New description from server")
    }

    func testSQLiteBackendPatchTaskStateAndAssigneeReviewerAndRelationships() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let patchedState = try backend.patchTaskState(taskID: "task-1", state: "done")
        XCTAssertEqual(stateID(in: patchedState), "done")
        XCTAssertEqual(stateLabel(in: patchedState), "Done")

        let clearedAssignee = try backend.patchTaskAssignee(taskID: "task-1", assigneeID: nil)
        XCTAssertTrue((clearedAssignee?["assignee_id"] is NSNull))

        let reassigned = try backend.patchTaskAssignee(taskID: "task-1", assigneeID: "user-1")
        XCTAssertEqual(reassigned?["assignee_id"] as? String, "user-1")

        let clearedReviewers = try backend.replaceTaskReviewers(taskID: "task-1", reviewerIDs: [])
        XCTAssertEqual(clearedReviewers?["reviewer_ids"] as? [String], [])

        let reReviewed = try backend.replaceTaskReviewers(taskID: "task-1", reviewerIDs: ["user-1"])
        XCTAssertEqual(reReviewed?["reviewer_ids"] as? [String], ["user-1"])

        let rewatched = try backend.replaceTaskWatchers(taskID: "task-1", watcherIDs: ["user-1"])
        XCTAssertEqual(rewatched?["watcher_ids"] as? [String], ["user-1"])

        let clearedWatchers = try backend.replaceTaskWatchers(taskID: "task-1", watcherIDs: [])
        XCTAssertEqual(clearedWatchers?["watcher_ids"] as? [String], [])
    }

    func testCreateTaskFromBodyDict() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let body: [String: Any] = [
            "project_id": "project-1",
            "title": "New task from body",
            "description": "Body description",
            "state": ["id": "inProgress"],
            "assignee_id": "user-1",
            "author_id": "user-1"
        ]

        let created = try backend.createTask(body: body)

        guard let newTaskID = created["id"] as? String else {
            XCTFail("Expected created task id")
            return
        }
        XCTAssertFalse(newTaskID.isEmpty)
        XCTAssertEqual(created["project_id"] as? String, "project-1")
        XCTAssertEqual(created["assignee_id"] as? String, "user-1")
        XCTAssertEqual(created["author_id"] as? String, "user-1")
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
            "project_id": "project-1",
            "title": "Unassigned task",
            "description": "No one yet",
            "state": ["id": "todo"],
            "author_id": "user-1"
        ]

        let created = try backend.createTask(body: body)
        XCTAssertTrue(created["assignee_id"] is NSNull || created["assignee_id"] == nil)
    }

    func testCreateTaskFromBodyDictValidation() throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let base: [String: Any] = [
            "project_id": "project-1",
            "title": "Valid title",
            "description": "Valid desc",
            "state": ["id": "todo"],
            "author_id": "user-1"
        ]

        // missing project_id
        var missingProject = base
        missingProject.removeValue(forKey: "project_id")
        XCTAssertThrowsError(try backend.createTask(body: missingProject))

        // unknown project_id
        var badProject = base
        badProject["project_id"] = "project-999"
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
        badAuthor["author_id"] = "user-999"
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
            "project_id": "project-1",
            "title": "New task",
            "description": "Server description",
            "state": ["id": "todo"],
            "assignee_id": "user-1",
            "author_id": "user-1"
        ]

        let created = try backend.createTask(body: body)

        guard let newTaskID = created["id"] as? String else {
            XCTFail("Expected created task id")
            return
        }
        XCTAssertEqual(created["project_id"] as? String, "project-1")
        XCTAssertEqual(created["assignee_id"] as? String, "user-1")
        XCTAssertEqual(created["reviewer_ids"] as? [String], [])
        XCTAssertEqual(created["author_id"] as? String, "user-1")
        XCTAssertEqual(created["watcher_ids"] as? [String], [])
        XCTAssertEqual(stateID(in: created), "todo")
        XCTAssertEqual(stateLabel(in: created), "To Do")

        let projectTasksAfterCreate = try backend.getProjectTasksPayload(projectID: "project-1")
        XCTAssertEqual(projectTasksAfterCreate.count, 2)
        XCTAssertTrue(projectTasksAfterCreate.contains { ($0["id"] as? String) == newTaskID })

        try backend.deleteTask(taskID: newTaskID)

        XCTAssertNil(try backend.getTaskDetailPayload(taskID: newTaskID))

        let projectTasksAfterDelete = try backend.getProjectTasksPayload(projectID: "project-1")
        XCTAssertEqual(projectTasksAfterDelete.count, 1)
        XCTAssertEqual(projectTasksAfterDelete[0]["id"] as? String, "task-1")
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
            _ = try backend.getProjectTasksPayload(projectID: "project-1")
        }

        let projectTasks = try backend.getProjectTasksPayload(projectID: "project-1")
        XCTAssertFalse(projectTasks.isEmpty)
        XCTAssertTrue(projectTasks.allSatisfy { ($0["project_id"] as? String) == "project-1" })

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
            projects: [.init(id: "project-1", name: "Project", updatedAt: now)],
            users: [.init(id: "user-1", displayName: "User", role: "Engineer", updatedAt: now)],
            tasks: [
                .init(
                    id: "task-1",
                    projectID: "project-1",
                    assigneeID: "user-1",
                    reviewerIDs: ["user-1"],
                    title: "Task 1",
                    descriptionText: "Old description",
                    state: "todo",
                    watcherIDs: ["user-1"],
                    updatedAt: now
                )
            ]
        )
    }
}
