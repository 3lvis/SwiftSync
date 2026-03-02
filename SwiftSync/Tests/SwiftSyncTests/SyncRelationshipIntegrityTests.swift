import XCTest
import SwiftData
@testable import SwiftSync

// Models that mirror the exact Demo pattern: Task owns @Relationship reviewers: [User]
// where User has NO back-reference property at all. This is the one-sided relationship
// pattern that triggers SwiftData's dirty-tracking gap on persistent stores.
@Model
final class OneSidedUser {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class OneSidedTask {
    @Attribute(.unique) var id: Int
    var title: String

    // No explicit inverse — OneSidedUser has no back-reference to OneSidedTask.
    // This is the same pattern as Task.reviewers / Task.watchers in the Demo.
    @Relationship var members: [OneSidedUser]

    init(id: Int, title: String, members: [OneSidedUser] = []) {
        self.id = id
        self.title = title
        self.members = members
    }
}

extension OneSidedUser: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<OneSidedUser, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OneSidedUser {
        OneSidedUser(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incoming: String = try payload.required(String.self, for: "name")
            if name != incoming { name = incoming; changed = true }
        }
        return changed
    }
}

extension OneSidedTask: SyncUpdatableModel {
    // Spy counter: incremented by syncMarkChanged() so tests can assert it was called.
    nonisolated(unsafe) static var syncMarkChangedCallCount: Int = 0

    typealias SyncID = Int
    static var syncIdentity: KeyPath<OneSidedTask, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OneSidedTask {
        OneSidedTask(
            id: try payload.required(Int.self, for: "id"),
            title: try payload.required(String.self, for: "title")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("title") {
            let incoming: String = try payload.required(String.self, for: "title")
            if title != incoming { title = incoming; changed = true }
        }
        return changed
    }

    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool {
        try syncApplyToManyForeignKeys(
            self,
            relationship: \OneSidedTask.members,
            payload: payload,
            keys: ["member_ids"],
            in: context,
            operations: operations
        )
    }

    func syncMarkChanged() {
        OneSidedTask.syncMarkChangedCallCount += 1
    }
}

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

    // Regression: after a to-many relationship-only sync (no scalar field changes),
    // Regression: syncApplyToManyForeignKeys must call syncMarkChanged() on the owning
    // model after any to-many membership change.
    //
    // Why this matters: on iOS with a persistent SQLite store, SwiftData only marks the
    // owning model's store row dirty when a *scalar* column changes. Mutating a to-many
    // relationship key path only dirties the join-table rows. As a result, the owner's
    // PersistentIdentifier is absent from NSManagedObjectContextDidSave's updatedObjects,
    // modelContextDidSave never faults the owner into mainContext, and @SyncModel /
    // @SyncQuery serve stale relationship data until the next background poll.
    //
    // The fix is for syncApplyToManyForeignKeys to call owner.syncMarkChanged() after
    // writing a new membership set. This forces a no-op scalar write (self.id = self.id)
    // that marks the owner's Core Data row dirty, guaranteeing the identifier surfaces
    // in the save notification.
    //
    // This test is fully platform-independent: it verifies the behavioral contract
    // (syncMarkChanged is called) directly, without relying on CoreData notification
    // semantics that differ between macOS and iOS.
    @MainActor
    func testSyncApplyToManyForeignKeysCallsSyncMarkChangedAfterMembershipChange() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedTask.self,
            OneSidedUser.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        // Seed two users and a task with no members.
        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Alice"], ["id": 2, "name": "Bob"]],
            as: OneSidedUser.self,
            in: context
        )
        try await SwiftSync.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [] as [Int]]],
            as: OneSidedTask.self,
            in: context
        )

        let task = try XCTUnwrap(
            context.fetch(FetchDescriptor<OneSidedTask>()).first
        )
        XCTAssertEqual(task.members.count, 0, "precondition: task starts with no members")

        // Reset the spy counter before the sync-under-test.
        OneSidedTask.syncMarkChangedCallCount = 0

        // Sync a relationship-only change: title unchanged, member_ids [] → [1, 2].
        try await SwiftSync.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]],
            as: OneSidedTask.self,
            in: context
        )

        // syncApplyToManyForeignKeys must have called syncMarkChanged() exactly once.
        // Without the fix this count is 0 and the test fails, reproducing the bug.
        XCTAssertEqual(
            OneSidedTask.syncMarkChangedCallCount, 1,
            "syncApplyToManyForeignKeys must call syncMarkChanged() after a membership " +
            "change so the owning model's store row is marked dirty on iOS persistent stores."
        )

        // Relationship data must also be correct.
        XCTAssertEqual(Set(task.members.map(\.id)), Set([1, 2]))
    }

    // Verify syncMarkChanged() is NOT called when membership is unchanged.
    @MainActor
    func testSyncApplyToManyForeignKeysDoesNotCallSyncMarkChangedWhenUnchanged() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedTask.self,
            OneSidedUser.self,
            configurations: configuration
        )
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Alice"], ["id": 2, "name": "Bob"]],
            as: OneSidedUser.self,
            in: context
        )
        try await SwiftSync.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]],
            as: OneSidedTask.self,
            in: context
        )

        OneSidedTask.syncMarkChangedCallCount = 0

        // Sync with the same membership — no change should occur.
        try await SwiftSync.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]],
            as: OneSidedTask.self,
            in: context
        )

        XCTAssertEqual(
            OneSidedTask.syncMarkChangedCallCount, 0,
            "syncMarkChanged() must not be called when relationship membership is unchanged."
        )
    }
}
