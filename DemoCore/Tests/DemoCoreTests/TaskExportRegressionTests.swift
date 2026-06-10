import SwiftData
import SwiftSync
import XCTest

@testable import DemoCore

// Guards `SyncContainer.export(_:)` for a Task draft — the payload the task-form
// save path builds before calling the API. A stale export API call here once
// broke the DemoCore build silently (it was never exercised by a test).
final class TaskExportRegressionTests: XCTestCase {

    @MainActor
    func testExportTaskProducesRemoteKeyedPayload() throws {
        let syncContainer = try makeSyncContainer()
        let task = Task(
            id: "T-1",
            projectID: "P-1",
            assigneeID: "U-2",
            authorID: "U-1",
            title: "Ship it",
            descriptionText: "Body text",
            state: "open",
            stateLabel: "Open"
        )
        syncContainer.mainContext.insert(task)

        let body = syncContainer.export(task)

        XCTAssertEqual(body["id"] as? String, "T-1")
        XCTAssertEqual(body["title"] as? String, "Ship it")
        XCTAssertEqual(body["description"] as? String, "Body text")
        XCTAssertEqual(body["project_id"] as? String, "P-1")
        XCTAssertEqual(body["author_id"] as? String, "U-1")
        XCTAssertEqual(body["assignee_id"] as? String, "U-2")

        let state = body["state"] as? [String: Any]
        XCTAssertEqual(state?["id"] as? String, "open")
        XCTAssertEqual(state?["label"] as? String, "Open")

        // @NotExport relationships must be excluded from the payload.
        XCTAssertNil(body["reviewers"])
        XCTAssertNil(body["watchers"])
        XCTAssertNil(body["assignee"])
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
}
