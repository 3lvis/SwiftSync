import SwiftData
import SwiftSync
import XCTest
@testable import DemoCore

final class DirtyTrackingGapTests: XCTestCase {

    private var storeURL: URL?

    override func tearDown() {
        super.tearDown()
        if let url = storeURL {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        storeURL = nil
    }

    private func makeTemporaryStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirtyTrackingGapTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).store")
        storeURL = url
        return url
    }

    @MainActor
    func testToManyOnlyWriteIncludesOwnerInNotification_persistentStore() async throws {
        let config = ModelConfiguration(url: makeTemporaryStoreURL())
        let container = try ModelContainer(
            for: Task.self, User.self, Project.self, TaskStateOption.self,
            configurations: config
        )
        try await runDirtyTrackingTest(container: container, label: "persistent")
    }

    @MainActor
    func testToManyOnlyWriteIncludesOwnerInNotification_inMemoryStore() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Task.self, User.self, Project.self, TaskStateOption.self,
            configurations: config
        )
        try await runDirtyTrackingTest(container: container, label: "in-memory")
    }

    @MainActor
    private func runDirtyTrackingTest(container: ModelContainer, label: String) async throws {
        let mainContext = container.mainContext

        let user1 = User(id: "u1", displayName: "Alice", createdAt: Date(), updatedAt: Date())
        let user2 = User(id: "u2", displayName: "Bob", createdAt: Date(), updatedAt: Date())
        let task = Task(id: "t1", projectID: "p1", assigneeID: nil, authorID: "u1",
                        title: "Test Task", descriptionText: "", state: "open", stateLabel: "Open",
                        createdAt: Date(), updatedAt: Date())
        mainContext.insert(user1)
        mainContext.insert(user2)
        mainContext.insert(task)
        try mainContext.save()

        let taskID = task.persistentModelID
        XCTAssertEqual(task.reviewers.count, 0)

        var updatedIDs: Set<PersistentIdentifier> = []
        var insertedIDs: Set<PersistentIdentifier> = []
        let saved = XCTestExpectation(description: "ModelContext.didSave")
        let bgContext = ModelContext(container)

        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: bgContext, queue: nil
        ) { notification in
            if let ui = notification.userInfo {
                if let ids = ui["updated"] as? [PersistentIdentifier] { updatedIDs = Set(ids) }
                if let ids = ui["inserted"] as? [PersistentIdentifier] { insertedIDs = Set(ids) }
            }
            saved.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let bgTasks = try bgContext.fetch(FetchDescriptor<Task>())
        guard let bgTask = bgTasks.first else { return XCTFail("Task not found") }
        try syncApplyToManyForeignKeys(
            bgTask,
            relationship: \Task.reviewers,
            payload: SyncPayload(values: ["reviewerIDs": ["u1", "u2"]]),
            keys: ["reviewerIDs"],
            in: bgContext
        )
        try bgContext.save()

        await fulfillment(of: [saved], timeout: 5)

        XCTAssertTrue(
            updatedIDs.contains(taskID) || insertedIDs.contains(taskID),
            "[\(label)] Task ID absent from didSave after syncApplyToManyForeignKeys. " +
            "updatedIDs: \(updatedIDs) insertedIDs: \(insertedIDs)"
        )

        mainContext.processPendingChanges()
        let refreshed = try mainContext.fetch(FetchDescriptor<Task>())
        XCTAssertEqual(refreshed.first?.reviewers.count, 2, "[\(label)] Relationship not written")
    }

}
