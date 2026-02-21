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
}
