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

    // MARK: - Predicate filtering

    @MainActor
    func testPublisherWithPredicateFiltersRows() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        try await syncContainer.sync(
            payload: [
                ["id": "t1", "title": "Alpha", "assignee_id": "u1"],
                ["id": "t2", "title": "Beta",  "assignee_id": NSNull()],
                ["id": "t3", "title": "Gamma", "assignee_id": "u1"],
            ],
            as: PubTask.self
        )

        let predicate = #Predicate<PubTask> { $0.assigneeID == "u1" }
        let publisher = SyncQueryPublisher(
            PubTask.self,
            predicate: predicate,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.map(\.id).sorted(), ["t1", "t3"])
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

        let originalRows = publisher.rows.map(\.id)

        try await syncContainer.sync(
            payload: [["id": "tag1", "name": "swift"]],
            as: PubUnrelatedTag.self
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.map(\.id), originalRows)
    }

    // MARK: - postFetchFilter (relationship)

    @MainActor
    func testPublisherWithToOneRelationshipIDFilter() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        try await syncContainer.sync(
            payload: [
                ["id": "u1", "display_name": "Alice", "role": ["id": "eng", "label": "Engineer"]],
                ["id": "u2", "display_name": "Bob",   "role": ["id": "eng", "label": "Engineer"]],
            ],
            as: PubUser.self
        )

        try await syncContainer.sync(
            payload: [
                ["id": "t1", "title": "Alice Task 1", "assignee_id": "u1"],
                ["id": "t2", "title": "Alice Task 2", "assignee_id": "u1"],
                ["id": "t3", "title": "Bob Task",     "assignee_id": "u2"],
            ],
            as: PubTask.self
        )

        let publisher = SyncQueryPublisher(
            PubTask.self,
            relationship: \PubTask.assignee,
            relationshipID: "u1",
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.map(\.id).sorted(), ["t1", "t2"])
    }

    @MainActor
    func testPublisherWithToManyRelationshipIDFilter() async throws {
        let syncContainer = try makeContainer(modelTypes: RoleUser.self, RoleTicket.self)
        let context = syncContainer.mainContext

        let userA = RoleUser(id: 1, name: "A")
        let userB = RoleUser(id: 2, name: "B")
        let ticketA = RoleTicket(id: 10, title: "T-10", assignee: userA, reviewer: userB)
        let ticketB = RoleTicket(id: 11, title: "T-11", assignee: userB, reviewer: userA)

        context.insert(userA)
        context.insert(userB)
        context.insert(ticketA)
        context.insert(ticketB)
        try context.save()

        let publisher = SyncQueryPublisher(
            RoleUser.self,
            relationship: \RoleUser.assignedTickets,
            relationshipID: 10,
            in: syncContainer,
            sortBy: [SortDescriptor(\RoleUser.id)]
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.map(\.id), [1])
    }

    @MainActor
    func testPublisherReloadsWhenLoadedRowIDAppears() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        try await syncContainer.sync(
            payload: [["id": "u1", "display_name": "Alice", "role": ["id": "eng", "label": "Engineer"]]],
            as: PubUser.self
        )
        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Original", "assignee_id": "u1"]],
            as: PubTask.self
        )

        let publisher = SyncQueryPublisher(
            PubTask.self,
            relationship: \PubTask.assignee,
            relationshipID: "u1",
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        await Task.yield()
        XCTAssertEqual(publisher.rows.first?.title, "Original")

        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Updated", "assignee_id": "u1"]],
            as: PubTask.self
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.first?.title, "Updated")
    }

    // MARK: - Current rows surface

    @MainActor
    func testRowsReflectLatestValues() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        let publisher = SyncQueryPublisher(
            PubTask.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        XCTAssertTrue(publisher.rows.isEmpty)

        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Alpha", "assignee_id": NSNull()]],
            as: PubTask.self
        )
        await Task.yield()
        XCTAssertEqual(publisher.rows.map(\.id), ["t1"])
    }

    @MainActor
    func testModelPublisherRefreshesSingleRowAfterBackgroundContextUpdate() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        try await syncContainer.sync(
            payload: [
                ["id": "u1", "display_name": "Alice", "role": ["id": "eng", "label": "Engineer"]],
                ["id": "u2", "display_name": "Bob", "role": ["id": "eng", "label": "Engineer"]]
            ],
            as: PubUser.self
        )
        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Original", "assignee_id": NSNull()]],
            as: PubTask.self
        )

        let publisher = SyncModelPublisher(
            PubTask.self,
            id: "t1",
            in: syncContainer
        )

        XCTAssertEqual(publisher.row?.id, "t1")
        XCTAssertNil(publisher.row?.assigneeID)

        let backgroundContext = ModelContext(syncContainer.modelContainer)
        let backgroundTask = try XCTUnwrap(
            backgroundContext.fetch(FetchDescriptor<PubTask>(predicate: #Predicate { $0.id == "t1" })).first
        )
        let backgroundAssignee = try XCTUnwrap(
            backgroundContext.fetch(FetchDescriptor<PubUser>(predicate: #Predicate { $0.id == "u2" })).first
        )
        backgroundTask.assigneeID = backgroundAssignee.id
        backgroundTask.assignee = backgroundAssignee
        try backgroundContext.save()

        try await waitUntil("single-row publisher refreshes changed assignee") {
            publisher.row?.assigneeID == "u2" && publisher.row?.assignee?.id == "u2"
        }

        XCTAssertEqual(publisher.row?.assigneeID, "u2")
        XCTAssertEqual(publisher.row?.assignee?.id, "u2")
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await _Concurrency.Task.sleep(nanoseconds: pollNanoseconds)
        }
        XCTFail("Timed out waiting for condition: \(description)")
    }
}
