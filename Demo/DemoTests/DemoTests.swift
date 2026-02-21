import SwiftData
import SwiftSync
import XCTest
@testable import Demo

final class DemoTests: XCTestCase {
    @MainActor
    func testFakeSeedDataCounts() {
        let seed = DemoSeedData.generate()
        XCTAssertEqual(seed.projects.count, 30)
        XCTAssertEqual(seed.users.count, 40)
        XCTAssertEqual(seed.tags.count, 50)
        XCTAssertEqual(seed.tasks.count, 300)
        XCTAssertEqual(seed.comments.count, 2_000)
    }

    @MainActor
    func testInitialSyncPopulatesCoreDataSets() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(
            for: Project.self,
            User.self,
            Task.self,
            Tag.self,
            Comment.self,
            configurations: configuration
        )
        let client = FakeDemoAPIClient(scenario: .fastStable, seedData: .generate())
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: client)

        await engine.syncInitialData()
        XCTAssertNil(engine.lastErrorMessage)

        let projects = try syncContainer.mainContext.fetch(FetchDescriptor<Project>())
        let users = try syncContainer.mainContext.fetch(FetchDescriptor<User>())
        let tags = try syncContainer.mainContext.fetch(FetchDescriptor<Tag>())

        XCTAssertEqual(projects.count, 30)
        XCTAssertEqual(users.count, 40)
        XCTAssertEqual(tags.count, 50)

        await engine.syncProjectTasks(projectID: "project-1")
        XCTAssertNil(engine.lastErrorMessage)
        let tasks = try syncContainer.mainContext.fetch(FetchDescriptor<Task>())
        XCTAssertFalse(tasks.isEmpty)
    }

    @MainActor
    func testFakeAPIEmitsExplicitNullForOptionalTaskFields() async throws {
        let now = Date()
        let seed = DemoSeedData(
            projects: [
                .init(id: "project-1", name: "P", status: "active", updatedAt: now)
            ],
            users: [
                .init(id: "user-1", displayName: "U", avatarSeed: "u1", role: "engineer", updatedAt: now)
            ],
            tags: [
                .init(id: "tag-1", name: "T", colorHex: "#000000", updatedAt: now)
            ],
            tasks: [
                .init(
                    id: "task-1",
                    projectID: "project-1",
                    assigneeID: nil,
                    title: "Task",
                    descriptionText: "Desc",
                    state: "todo",
                    priority: 1,
                    dueDate: nil,
                    tagIDs: ["tag-1"],
                    updatedAt: now
                )
            ],
            comments: []
        )
        let client = FakeDemoAPIClient(scenario: .fastStable, seedData: seed)

        let rows = try await client.getProjectTasks(projectID: "project-1")
        XCTAssertEqual(rows.count, 1)

        let row = rows[0]
        XCTAssertNotNil(row["id"])
        XCTAssertNotNil(row["project_id"])
        XCTAssertNotNil(row["assignee_id"])
        XCTAssertNotNil(row["due_date"])
        XCTAssertNotNil(row["tag_ids"])
        XCTAssertNotNil(row["description_text"])
        XCTAssertNotNil(row["updated_at"])

        XCTAssertTrue(row["assignee_id"] is NSNull)
        XCTAssertTrue(row["due_date"] is NSNull)
        XCTAssertEqual(row["tag_ids"] as? [String], ["tag-1"])
    }

    @MainActor
    func testFakeAPIUsesSyncRelationshipKeyConventions() async throws {
        let now = Date()
        let seed = DemoSeedData(
            projects: [
                .init(id: "project-1", name: "P", status: "active", updatedAt: now)
            ],
            users: [
                .init(id: "user-1", displayName: "U", avatarSeed: "u1", role: "engineer", updatedAt: now)
            ],
            tags: [],
            tasks: [
                .init(
                    id: "task-1",
                    projectID: "project-1",
                    assigneeID: "user-1",
                    title: "Task",
                    descriptionText: "Desc",
                    state: "todo",
                    priority: 1,
                    dueDate: now,
                    tagIDs: [],
                    updatedAt: now
                )
            ],
            comments: [
                .init(
                    id: "comment-1",
                    taskID: "task-1",
                    authorUserID: "user-1",
                    body: "Hello",
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )
        let client = FakeDemoAPIClient(scenario: .fastStable, seedData: seed)

        let taskRows = try await client.getProjectTasks(projectID: "project-1")
        XCTAssertEqual(taskRows.count, 1)
        XCTAssertNotNil(taskRows[0]["project_id"])
        XCTAssertNotNil(taskRows[0]["assignee_id"])
        XCTAssertNotNil(taskRows[0]["tag_ids"])
        XCTAssertNotNil(taskRows[0]["description_text"])
        XCTAssertNil(taskRows[0]["project"])
        XCTAssertNil(taskRows[0]["assignee"])
        XCTAssertNil(taskRows[0]["tags"])

        let commentRows = try await client.getTaskComments(taskID: "task-1")
        XCTAssertEqual(commentRows.count, 1)
        XCTAssertNotNil(commentRows[0]["task_id"])
        XCTAssertNotNil(commentRows[0]["author_user_id"])
        XCTAssertNil(commentRows[0]["task"])
        XCTAssertNil(commentRows[0]["author"])
    }
}
