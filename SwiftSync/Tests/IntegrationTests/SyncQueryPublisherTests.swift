import Combine
import XCTest
import SwiftData
import SwiftSync

// ---------------------------------------------------------------------------
// Minimal models used only in these tests
// ---------------------------------------------------------------------------

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

/// A model with no relationship to PubTask or PubUser, used to verify that
/// publishing changes to it does not trigger a PubTask publisher reload.
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

final class SyncQueryPublisherTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func makeContainer(modelTypes: any PersistentModel.Type...) throws -> SyncContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: Schema(modelTypes), configurations: config)
        return SyncContainer(modelContainer)
    }

    // MARK: - Basic population

    /// Publisher emits the initial set of rows on creation.
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

    /// Publisher updates its rows after a sync() call adds a new model.
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

        // Give the main run-loop one cycle so the notification fires.
        await Task.yield()

        XCTAssertEqual(publisher.rows.map(\.id), ["t1"])
    }

    /// Publisher reflects an update to an existing row after a subsequent sync.
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

    /// Publisher with a predicate only returns rows matching that predicate.
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

    /// A publisher for a model that has no relationship to the changed type does not reload.
    ///
    /// PubUnrelatedTag has no relationship to PubTask, so a PubTask publisher should
    /// not reload when only PubUnrelatedTag rows change.
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
            .dropFirst() // skip initial value
            .sink { _ in reloadCount += 1 }
            .store(in: &cancellables)

        // Sync only PubUnrelatedTag rows — PubTask publisher should not fire.
        try await syncContainer.sync(
            payload: [["id": "tag1", "name": "swift"]],
            as: PubUnrelatedTag.self
        )

        await Task.yield()

        XCTAssertEqual(reloadCount, 0)
    }

    // MARK: - postFetchFilter (relatedTo)

    /// Publisher with an explicit post-fetch filter (to-one) only returns matching rows.
    @MainActor
    func testPublisherWithToOneRelatedIDFilter() async throws {
        let syncContainer = try makeContainer(modelTypes: PubTask.self, PubUser.self)

        // Insert users
        try await syncContainer.sync(
            payload: [
                ["id": "u1", "display_name": "Alice", "role": ["id": "eng", "label": "Engineer"]],
                ["id": "u2", "display_name": "Bob",   "role": ["id": "eng", "label": "Engineer"]],
            ],
            as: PubUser.self
        )

        // Insert tasks with assignees
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
            relatedTo: PubUser.self,
            relatedID: "u1",
            through: \PubTask.assignee,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.map(\.id).sorted(), ["t1", "t2"])
    }

    /// Publisher with a to-one filter reloads when a previously-loaded row changes.
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
            relatedTo: PubUser.self,
            relatedID: "u1",
            through: \PubTask.assignee,
            in: syncContainer,
            sortBy: [SortDescriptor(\PubTask.title)]
        )

        await Task.yield()
        XCTAssertEqual(publisher.rows.first?.title, "Original")

        // Update the task title — publisher should see the new value.
        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Updated", "assignee_id": "u1"]],
            as: PubTask.self
        )

        await Task.yield()

        XCTAssertEqual(publisher.rows.first?.title, "Updated")
    }

    // MARK: - Combine publisher surface

    /// rowsPublisher emits the same values as rows.
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

        // Initial emission.
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
