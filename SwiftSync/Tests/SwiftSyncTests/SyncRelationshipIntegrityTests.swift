import XCTest
import SwiftData
@testable import SwiftSync

@Model
final class MissingInverseRegressionTag {
    @Attribute(.unique) var id: Int
    var name: String
    // Intentionally missing explicit inverse to reproduce the bug we saw in Demo.
    var tasks: [MissingInverseRegressionTask]

    init(id: Int, name: String, tasks: [MissingInverseRegressionTask] = []) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}

@Model
final class MissingInverseRegressionTask {
    @Attribute(.unique) var id: Int
    var title: String

    @RemoteKey("tag_ids")
    var tags: [MissingInverseRegressionTag]

    init(id: Int, title: String, tags: [MissingInverseRegressionTag] = []) {
        self.id = id
        self.title = title
        self.tags = tags
    }
}

@Model
final class ExplicitInverseRegressionTag {
    @Attribute(.unique) var id: Int
    var name: String
    var tasks: [ExplicitInverseRegressionTask]

    init(id: Int, name: String, tasks: [ExplicitInverseRegressionTask] = []) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}

@Model
final class ExplicitInverseRegressionTask {
    @Attribute(.unique) var id: Int
    var title: String

    @RemoteKey("tag_ids")
    @Relationship(inverse: \ExplicitInverseRegressionTag.tasks)
    var tags: [ExplicitInverseRegressionTag]

    init(id: Int, title: String, tags: [ExplicitInverseRegressionTag] = []) {
        self.id = id
        self.title = title
        self.tags = tags
    }
}

extension MissingInverseRegressionTag: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<MissingInverseRegressionTag, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> MissingInverseRegressionTag {
        MissingInverseRegressionTag(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incomingName: String = try payload.required(String.self, for: "name")
            if name != incomingName {
                name = incomingName
                changed = true
            }
        }
        return changed
    }
}

extension MissingInverseRegressionTask: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<MissingInverseRegressionTask, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> MissingInverseRegressionTask {
        MissingInverseRegressionTask(
            id: try payload.required(Int.self, for: "id"),
            title: try payload.required(String.self, for: "title")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("title") {
            let incomingTitle: String = try payload.required(String.self, for: "title")
            if title != incomingTitle {
                title = incomingTitle
                changed = true
            }
        }
        return changed
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool {
        try syncApplyToManyForeignKeys(
            self,
            relationship: \MissingInverseRegressionTask.tags,
            payload: payload,
            keys: ["tag_ids"],
            in: context,
            operations: operations
        )
    }

    func syncMarkChanged() { self.id = self.id }
}

extension ExplicitInverseRegressionTag: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<ExplicitInverseRegressionTag, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> ExplicitInverseRegressionTag {
        ExplicitInverseRegressionTag(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incomingName: String = try payload.required(String.self, for: "name")
            if name != incomingName {
                name = incomingName
                changed = true
            }
        }
        return changed
    }
}

extension ExplicitInverseRegressionTask: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<ExplicitInverseRegressionTask, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> ExplicitInverseRegressionTask {
        ExplicitInverseRegressionTask(
            id: try payload.required(Int.self, for: "id"),
            title: try payload.required(String.self, for: "title")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("title") {
            let incomingTitle: String = try payload.required(String.self, for: "title")
            if title != incomingTitle {
                title = incomingTitle
                changed = true
            }
        }
        return changed
    }

    func syncMarkChanged() { self.id = self.id }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool {
        try syncApplyToManyForeignKeys(
            self,
            relationship: \ExplicitInverseRegressionTask.tags,
            payload: payload,
            keys: ["tag_ids"],
            in: context,
            operations: operations
        )
    }
}

final class RelationshipIntegrityRegressionTests: XCTestCase {
    @MainActor
    func testMissingExplicitInverseCanDropSharedTagMembershipAcrossTaskBatchSync() async throws {
        XCTExpectFailure(
            "Known SwiftData/SwiftSync runtime bug: a many-to-many pair with no explicit inverse anchor can corrupt shared memberships during batch sync. Use one explicit @Relationship(inverse: ...) anchor until runtime guardrails are added."
        )

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MissingInverseRegressionTask.self,
            MissingInverseRegressionTag.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "name": "Tag 1"],
                ["id": 2, "name": "Tag 2"],
                ["id": 3, "name": "Tag 3"]
            ],
            as: MissingInverseRegressionTag.self,
            in: context
        )

        // Mirrors the demo flow: a single-task sync happens first after a mutation.
        try await SwiftSync.sync(
            payload: [[
                "id": 10,
                "title": "Task 10",
                "tag_ids": [1, 2]
            ]],
            as: MissingInverseRegressionTask.self,
            in: context
        )

        // Then a task-list batch sync arrives with another task sharing one tag.
        try await SwiftSync.sync(
            payload: [
                ["id": 10, "title": "Task 10", "tag_ids": [1, 2]],
                ["id": 20, "title": "Task 20", "tag_ids": [2, 3]]
            ],
            as: MissingInverseRegressionTask.self,
            in: context
        )

        let tasks = try context.fetch(FetchDescriptor<MissingInverseRegressionTask>())
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, Set($0.tags.map(\.id))) })

        XCTAssertEqual(tasksByID[10], Set([1, 2]))
        XCTAssertEqual(tasksByID[20], Set([2, 3]))
    }

    @MainActor
    func testExplicitInversePreservesSharedTagMembershipAcrossTaskBatchSync() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ExplicitInverseRegressionTask.self,
            ExplicitInverseRegressionTag.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "name": "Tag 1"],
                ["id": 2, "name": "Tag 2"],
                ["id": 3, "name": "Tag 3"]
            ],
            as: ExplicitInverseRegressionTag.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [[
                "id": 10,
                "title": "Task 10",
                "tag_ids": [1, 2]
            ]],
            as: ExplicitInverseRegressionTask.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [
                ["id": 10, "title": "Task 10", "tag_ids": [1, 2]],
                ["id": 20, "title": "Task 20", "tag_ids": [2, 3]]
            ],
            as: ExplicitInverseRegressionTask.self,
            in: context
        )

        let tasks = try context.fetch(FetchDescriptor<ExplicitInverseRegressionTask>())
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, Set($0.tags.map(\.id))) })

        XCTAssertEqual(tasksByID[10], Set([1, 2]))
        XCTAssertEqual(tasksByID[20], Set([2, 3]))
    }

    // Regression: syncing a to-many relationship change must surface the owning
    // model's PersistentIdentifier in the SyncContainer.didSaveChangesNotification.
    //
    // If the identifier is absent, SyncQueryObserver.shouldReload never invalidates
    // the owning model in mainContext, so @SyncModel / @SyncQuery return stale
    // relationship data until the next background poll.
    //
    // Root cause: SwiftData only marks a model's store row dirty (and thus includes
    // its identifier in NSManagedObjectContextDidSave's updatedObjects) when a scalar
    // column changes. Mutating a to-many key path only dirties the join-table rows,
    // not the owning row. syncApplyToManyForeignKeys must force a scalar touch on the
    // owning model after a membership change so the identifier surfaces correctly.
    // Regression: SyncContainer.didSaveChangesNotification must include the owning
    // model's PersistentIdentifier after a to-many relationship-only sync.
    //
    // In a persistent (on-disk) SQLite store, SwiftData only marks an owning model's
    // store row dirty when a scalar column changes. Mutating a to-many key path only
    // dirties the join-table rows, so the owner's identifier is absent from
    // NSManagedObjectContextDidSave's updatedObjects. modelContextDidSave therefore
    // never faults the owner into mainContext, and @SyncModel / @SyncQuery serve
    // stale relationship data until the next background poll.
    //
    // The fix is in syncApplyToManyForeignKeys: after writing the new membership,
    // perform a no-op scalar write on the owning model to guarantee its store row
    // is dirtied and its identifier surfaces in the save notification.
    //
    // NOTE: In-memory SQLite stores (used in tests) always dirty the owner regardless,
    // so this specific assertion cannot be driven to failure in a unit test. The test
    // is kept as documentation of the contract and as a non-regression anchor — it
    // will catch any future regression that breaks the relationship update itself.
    @MainActor
    func testToManyRelationshipOnlySyncUpdatesMainContextImmediately() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: MissingInverseRegressionTask.self,
            MissingInverseRegressionTag.self,
            configurations: configuration
        )
        let syncContainer = SyncContainer(modelContainer)

        // Seed two tags and a task that starts with no tags.
        try await syncContainer.sync(
            payload: [["id": 1, "name": "Tag 1"], ["id": 2, "name": "Tag 2"]],
            as: MissingInverseRegressionTag.self
        )
        try await syncContainer.sync(
            payload: [["id": 10, "title": "Task 10", "tag_ids": [] as [Int]]],
            as: MissingInverseRegressionTask.self
        )
        let taskID = try XCTUnwrap(
            syncContainer.mainContext.fetch(FetchDescriptor<MissingInverseRegressionTask>()).first?.persistentModelID
        )
        let initialTags = try syncContainer.mainContext.fetch(FetchDescriptor<MissingInverseRegressionTask>()).first?.tags.count ?? 0
        XCTAssertEqual(initialTags, 0, "precondition: task starts with no tags")

        // Capture the notification produced by a relationship-only change.
        // Title is unchanged; only tag membership changes ([] → [1, 2]).
        let notificationIDs = try await capturedChangedIDs(from: syncContainer) {
            try await syncContainer.sync(
                payload: [["id": 10, "title": "Task 10", "tag_ids": [1, 2]]],
                as: MissingInverseRegressionTask.self
            )
        }

        // The owning task's identifier must appear in changedIDs so that
        // SyncQueryObserver can invalidate it in mainContext synchronously.
        XCTAssertTrue(
            notificationIDs.contains(taskID),
            "Owner identifier must be in didSaveChangesNotification changedIDs after " +
            "a to-many relationship-only change. Got: \(notificationIDs)"
        )

        // Relationship data must be correct in mainContext.
        let task = syncContainer.mainContext.model(for: taskID) as? MissingInverseRegressionTask
        XCTAssertEqual(Set(task?.tags.map(\.id) ?? []), Set([1, 2]))
    }

    /// Observes the first `SyncContainer.didSaveChangesNotification` emitted while
    /// `body` runs and returns the set of changed identifiers from that notification.
    @MainActor
    private func capturedChangedIDs(
        from syncContainer: SyncContainer,
        body: () async throws -> Void
    ) async throws -> Set<PersistentIdentifier> {
        var ids: Set<PersistentIdentifier> = []
        let exp = expectation(description: "didSaveChangesNotification")
        exp.assertForOverFulfill = false
        let token = NotificationCenter.default.addObserver(
            forName: SyncContainer.didSaveChangesNotification,
            object: syncContainer,
            queue: .main
        ) { notification in
            ids.formUnion(syncQueryChangedIdentifiers(from: notification.userInfo))
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        try await body()
        await fulfillment(of: [exp], timeout: 2)
        return ids
    }
}
