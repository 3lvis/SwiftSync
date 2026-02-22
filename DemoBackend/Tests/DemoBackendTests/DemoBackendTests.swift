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
        let tags = try backend.getTagsPayload()
        let projectTasks = try backend.getProjectTasksPayload(projectID: "project-1")
        let taskComments = try backend.getTaskCommentsPayload(taskID: "task-1")

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(projectTasks.count, 1)
        XCTAssertEqual(taskComments.count, 1)

        XCTAssertNil(users.first?["avatar_seed"])
        XCTAssertNil(tags.first?["color_hex"])
        XCTAssertNil(projectTasks.first?["due_date"])
        XCTAssertNil(projectTasks.first?["priority"])
        XCTAssertEqual(projectTasks.first?["tag_ids"] as? [String], ["tag-1", "tag-2"])
        XCTAssertNotNil(projectTasks.first?["description"])
        XCTAssertNotNil(projectTasks.first?["updated_at"])
        XCTAssertEqual(taskComments.first?["author_name"] as? String, "User")
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

    func testSQLiteBackendCreateCommentPersistsRelationshipRead() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let seed = DemoSeedData(
            projects: [.init(id: "project-1", name: "P", status: "active", updatedAt: Date(timeIntervalSince1970: 10))],
            users: [.init(id: "user-1", displayName: "U", role: "Engineer", updatedAt: Date(timeIntervalSince1970: 10))],
            tags: [],
            tasks: [
                .init(
                    id: "task-1",
                    projectID: "project-1",
                    assigneeID: nil,
                    title: "Task",
                    descriptionText: "Desc",
                    state: "todo",
                    tagIDs: [],
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            ],
            comments: []
        )

        let backend = try DemoServerSimulator(databaseURL: url, seedData: seed)
        let created = try backend.createComment(
            taskID: "task-1",
            authorUserID: "user-1",
            body: "Server-created comment"
        )

        XCTAssertEqual(created["task_id"] as? String, "task-1")
        XCTAssertEqual(created["author_user_id"] as? String, "user-1")
        XCTAssertEqual(created["author_name"] as? String, "U")
        XCTAssertEqual(created["body"] as? String, "Server-created comment")
        XCTAssertEqual(created["id"] as? String, "comment-1")
        XCTAssertNil(created["updated_at"])

        let comments = try backend.getTaskCommentsPayload(taskID: "task-1")
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(comments[0]["id"] as? String, "comment-1")
        XCTAssertEqual(comments[0]["author_name"] as? String, "U")
        XCTAssertNil(comments[0]["updated_at"])
    }

    func testSQLiteBackendDeleteCommentRemovesFromTaskComments() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        try backend.deleteComment(commentID: "comment-1")
        let comments = try backend.getTaskCommentsPayload(taskID: "task-1")
        XCTAssertTrue(comments.isEmpty)
    }

    func testSQLiteBackendPatchTaskStateAndAssigneeAndReplaceTags() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let before = try backend.getTaskDetailPayload(taskID: "task-1")
        let beforeUpdatedAt = before?["updated_at"] as? String

        let patchedState = try backend.patchTaskState(taskID: "task-1", state: "done")
        XCTAssertEqual(patchedState?["state"] as? String, "done")

        let clearedAssignee = try backend.patchTaskAssignee(taskID: "task-1", assigneeID: nil)
        XCTAssertTrue((clearedAssignee?["assignee_id"] is NSNull))

        let reassigned = try backend.patchTaskAssignee(taskID: "task-1", assigneeID: "user-1")
        XCTAssertEqual(reassigned?["assignee_id"] as? String, "user-1")

        let retagged = try backend.replaceTaskTags(taskID: "task-1", tagIDs: ["tag-2"])
        XCTAssertEqual(retagged?["tag_ids"] as? [String], ["tag-2"])
        XCTAssertNotEqual(retagged?["updated_at"] as? String, beforeUpdatedAt)

        let tag1Tasks = try backend.getTagTasksPayload(tagID: "tag-1")
        let tag2Tasks = try backend.getTagTasksPayload(tagID: "tag-2")
        XCTAssertTrue(tag1Tasks.isEmpty)
        XCTAssertEqual(tag2Tasks.map { $0["id"] as? String }, ["task-1"])
    }

    func testSQLiteBackendCreateAndDeleteTaskUpdatesProjectAndTagSlices() async throws {
        let url = makeTemporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let backend = try DemoServerSimulator(databaseURL: url, seedData: smallSeedData())

        let created = try backend.createTask(
            projectID: "project-1",
            title: "New task",
            descriptionText: "Server description",
            state: "todo",
            assigneeID: "user-1",
            tagIDs: ["tag-1"]
        )

        guard let newTaskID = created["id"] as? String else {
            XCTFail("Expected created task id")
            return
        }
        XCTAssertEqual(created["project_id"] as? String, "project-1")
        XCTAssertEqual(created["assignee_id"] as? String, "user-1")
        XCTAssertEqual(created["tag_ids"] as? [String], ["tag-1"])

        let projectTasksAfterCreate = try backend.getProjectTasksPayload(projectID: "project-1")
        XCTAssertEqual(projectTasksAfterCreate.count, 2)
        XCTAssertTrue(projectTasksAfterCreate.contains { ($0["id"] as? String) == newTaskID })

        _ = try backend.createComment(taskID: newTaskID, authorUserID: "user-1", body: "For cascade")
        XCTAssertEqual(try backend.getTaskCommentsPayload(taskID: newTaskID).count, 1)

        try backend.deleteTask(taskID: newTaskID)

        XCTAssertNil(try backend.getTaskDetailPayload(taskID: newTaskID))
        XCTAssertTrue(try backend.getTaskCommentsPayload(taskID: newTaskID).isEmpty)

        let projectTasksAfterDelete = try backend.getProjectTasksPayload(projectID: "project-1")
        XCTAssertEqual(projectTasksAfterDelete.count, 1)
        XCTAssertEqual(projectTasksAfterDelete[0]["id"] as? String, "task-1")

        let tag1TasksAfterDelete = try backend.getTagTasksPayload(tagID: "tag-1")
        XCTAssertEqual(tag1TasksAfterDelete.map { $0["id"] as? String }, ["task-1"])
    }

    private func makeTemporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoBackendTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func smallSeedData() -> DemoSeedData {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return DemoSeedData(
            projects: [.init(id: "project-1", name: "Project", status: "active", updatedAt: now)],
            users: [.init(id: "user-1", displayName: "User", role: "Engineer", updatedAt: now)],
            tags: [
                .init(id: "tag-1", name: "frontend", updatedAt: now),
                .init(id: "tag-2", name: "ios", updatedAt: now)
            ],
            tasks: [
                .init(
                    id: "task-1",
                    projectID: "project-1",
                    assigneeID: "user-1",
                    title: "Task 1",
                    descriptionText: "Old description",
                    state: "todo",
                    tagIDs: ["tag-1", "tag-2"],
                    updatedAt: now
                )
            ],
            comments: [
                .init(
                    id: "comment-1",
                    taskID: "task-1",
                    authorUserID: "user-1",
                    body: "Existing comment",
                    createdAt: now
                )
            ]
        )
    }
}
