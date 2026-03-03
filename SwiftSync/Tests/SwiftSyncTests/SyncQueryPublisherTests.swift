import Combine
import XCTest
import SwiftData
import SwiftSync

@Syncable
@Model
final class PubTask {
    @Attribute(.unique) var id: String
    var title: String
    var assigneeID: String?
    var assignee: PubUser?

    init(id: String, title: String, assigneeID: String? = nil, assignee: PubUser? = nil) {
        self.id = id
        self.title = title
        self.assigneeID = assigneeID
        self.assignee = assignee
    }
}

@Syncable
@Model
final class PubUser {
    @Attribute(.unique) var id: String
    var displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

// Unrelated to PubTask/PubUser — used to verify no spurious reloads across type boundaries.
@Syncable
@Model
final class PubUnrelatedTag {
    @Attribute(.unique) var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

final class SyncQueryPublisherTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func makeContainer(modelTypes: any PersistentModel.Type...) throws -> SyncContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: Schema(modelTypes), configurations: config)
        return SyncContainer(modelContainer)
    }

    // MARK: - Basic population

    @MainActor
    func testPublisherEmitsInitialRows() throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)
        let ctx = syncContainer.mainContext
        ctx.insert(PubTask(id: "t1", title: "Alpha"))
        ctx.insert(PubTask(id: "t2", title: "Beta"))
        try ctx.save()

        let publisher = SyncQueryPublisher(
            PubTask.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        XCTAssertEqual(publisher.rows.map(\.id), ["t1", "t2"])
    }

    // MARK: - Reactive reload after sync

    @MainActor
    func testPublisherReloadsAfterSync() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        let publisher = SyncQueryPublisher(
            PubTask.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        XCTAssertEqual(publisher.rows.count, 0)

        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Alpha", "assignee_id": NSNull()]],
            as: PubTask.self
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.map(\.id), ["t1"])
    }

    @MainActor
    func testPublisherReloadsAfterUpdate() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Old Title", "assignee_id": NSNull()]],
            as: PubTask.self
        )

        let publisher = SyncQueryPublisher(
            PubTask.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        XCTAssertEqual(publisher.rows.first?.title, "Old Title")

        try await syncContainer.sync(
            payload: [["id": "t1", "title": "New Title", "assignee_id": NSNull()]],
            as: PubTask.self
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.first?.title, "New Title")
    }

    // MARK: - No spurious reload for unrelated types

    @MainActor
    func testPublisherDoesNotReloadForUnrelatedTypeChange() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self, PubUnrelatedTag.self)

        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Alpha", "assignee_id": NSNull()]],
            as: PubTask.self
        )

        let publisher = SyncQueryPublisher(
            PubTask.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        var reloadCount = 0
        var cancellables = Set<AnyCancellable>()
        publisher.$rows
            .dropFirst()
            .sink { _ in reloadCount += 1 }
            .store(in: &cancellables)

        try await syncContainer.sync(
            payload: [["id": "tag1", "name": "swift"]],
            as: PubUnrelatedTag.self
        )

        await Task.yield()

        XCTAssertEqual(reloadCount, 0)
    }

    // MARK: - Combine publisher surface

    @MainActor
    func testRowsPublisherEmitsValues() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        let publisher = SyncQueryPublisher(
            PubTask.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        var received: [[PubTask]] = []
        var cancellables = Set<AnyCancellable>()
        publisher.rowsPublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received[0].isEmpty)

        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Alpha", "assignee_id": NSNull()]],
            as: PubTask.self
        )
        await Task.yield()

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[1].map(\.id), ["t1"])
    }
}
