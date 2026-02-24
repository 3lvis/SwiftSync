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
        let priorities = try backend.getPriorityOptionsPayload()
        let userRoles = try backend.getUserRoleOptionsPayload()
        let projectTasks = try backend.getProjectTasksPayload(projectID: "project-1")

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(taskStates.count, 3)
        XCTAssertEqual(priorities.count, 4)
        XCTAssertEqual(userRoles.count, 1)
        XCTAssertEqual(projectTasks.count, 1)

        XCTAssertEqual(userRoleID(in: users.first), "Engineer")
        XCTAssertEqual(userRoleLabel(in: users.first), "Engineer")
        XCTAssertNil(users.first?["avatar_seed"])
        XCTAssertNil(projectTasks.first?["due_date"])
        XCTAssertEqual(projectTasks.first?["reviewer_id"] as? String, "user-1")
        XCTAssertEqual(projectTasks.first?["author_id"] as? String, "user-1")
        XCTAssertEqual(projectTasks.first?["watcher_ids"] as? [String], ["user-1"])
        XCTAssertEqual(stateID(in: projectTasks.first), "todo")
        XCTAssertEqual(stateLabel(in: projectTasks.first), "To Do")
        XCTAssertEqual(taskPriorityID(in: projectTasks.first), "medium")
        XCTAssertEqual(taskPriorityLabel(in: projectTasks.first), "Medium")
        XCTAssertNotNil(projectTasks.first?["description"])
        XCTAssertNotNil(projectTasks.first?["updated_at"])
        XCTAssertEqual(taskStates.map { $0["id"] as? String }, ["todo", "inProgress", "done"])
        XCTAssertEqual(taskStates.map { ($0["label"] as? String) ?? "" }, ["To Do", "In Progress", "Done"])
        XCTAssertEqual(priorities.map { $0["id"] as? String }, ["low", "medium", "high", "urgent"])
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

        let before = try backend.getTaskDetailPayload(taskID: "task-1")
        let beforeUpdatedAt = before?["updated_at"] as? String

        let patchedState = try backend.patchTaskState(taskID: "task-1", state: "done")
        XCTAssertEqual(stateID(in: patchedState), "done")
        XCTAssertEqual(stateLabel(in: patchedState), "Done")

        let clearedAssignee = try backend.patchTaskAssignee(taskID: "task-1", assigneeID: nil)
        XCTAssertTrue((clearedAssignee?["assignee_id"] is NSNull))

        let reassigned = try backend.patchTaskAssignee(taskID: "task-1", assigneeID: "user-1")
        XCTAssertEqual(reassigned?["assignee_id"] as? String, "user-1")

        let clearedReviewer = try backend.patchTaskReviewer(taskID: "task-1", reviewerID: nil)
        XCTAssertTrue((clearedReviewer?["reviewer_id"] is NSNull))

        let reReviewed = try backend.patchTaskReviewer(taskID: "task-1", reviewerID: "user-1")
        XCTAssertEqual(reReviewed?["reviewer_id"] as? String, "user-1")

        let rewatched = try backend.replaceTaskWatchers(taskID: "task-1", watcherIDs: ["user-1"])
        XCTAssertEqual(rewatched?["watcher_ids"] as? [String], ["user-1"])

        let clearedWatchers = try backend.replaceTaskWatchers(taskID: "task-1", watcherIDs: [])
        XCTAssertEqual(clearedWatchers?["watcher_ids"] as? [String], [])
    }

    func testSQLiteBackendCreateAndDeleteTaskUpdatesProjectSlice() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let created = try backend.createTask(
            projectID: "project-1",
            title: "New task",
            descriptionText: "Server description",
            state: "todo",
            assigneeID: "user-1",
            authorID: "user-1"
        )

        guard let newTaskID = created["id"] as? String else {
            XCTFail("Expected created task id")
            return
        }
        XCTAssertEqual(created["project_id"] as? String, "project-1")
        XCTAssertEqual(created["assignee_id"] as? String, "user-1")
        XCTAssertTrue((created["reviewer_id"] is NSNull))
        XCTAssertEqual(created["author_id"] as? String, "user-1")
        XCTAssertEqual(created["watcher_ids"] as? [String], [])
        XCTAssertEqual(stateID(in: created), "todo")
        XCTAssertEqual(stateLabel(in: created), "To Do")
        XCTAssertEqual(taskPriorityID(in: created), "medium")
        XCTAssertEqual(taskPriorityLabel(in: created), "Medium")

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

    private func userRoleID(in user: [String: Any]?) -> String? {
        (user?["role"] as? [String: Any])?["id"] as? String
    }

    private func userRoleLabel(in user: [String: Any]?) -> String? {
        (user?["role"] as? [String: Any])?["label"] as? String
    }

    private func taskPriorityID(in task: [String: Any]?) -> String? {
        (task?["priority"] as? [String: Any])?["id"] as? String
    }

    private func taskPriorityLabel(in task: [String: Any]?) -> String? {
        (task?["priority"] as? [String: Any])?["label"] as? String
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
                    reviewerID: "user-1",
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
