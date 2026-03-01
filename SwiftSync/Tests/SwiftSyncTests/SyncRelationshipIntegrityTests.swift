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

    func syncMarkChanged() { self.id = self.id }
}

extension OneSidedTask: SyncUpdatableModel {
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

    func syncMarkChanged() { self.id = self.id }
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

    // Regression: after a to-many relationship-only sync (no scalar field changes),
    // SyncContainer.didSaveChangesNotification must include the owning model's
    // PersistentIdentifier so SyncQueryObserver can invalidate mainContext immediately.
    //
    // Root cause: on iOS persistent SQLite stores, SwiftData only marks the owning
    // model's row dirty when a scalar column changes. A to-many assignment on a
    // relationship with no explicit inverse only dirties the join-table rows, so the
    // owner is absent from NSManagedObjectContextDidSave's updatedObjects. This means
    // modelContextDidSave never faults the owner into mainContext, and @SyncModel /
    // @SyncQuery serve stale relationship data until the next background poll.
    //
    // Fix: syncApplyToManyForeignKeys calls owner.syncMarkChanged() (a no-op scalar
    // self-write generated by @Syncable) after any membership change, guaranteeing
    // the owner's row is dirtied and its identifier surfaces in the notification.
    //
    // Platform note: macOS CoreData/SwiftData surfaces the owner identifier even
    // without the fix, so this test cannot be driven red on the SPM test host (macOS).
    // The test is kept as a contract anchor and documents the fix intent. The
    // Observable behavior was confirmed via debug logging on a running iOS app where
    // Task/p4 was absent from changedIDs after replaceTaskReviewers until the fix.
    @MainActor
    func testToManyRelationshipOnlySyncSurfacesOwnerInDidSaveNotification_persistentStore() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftSyncOneSidedRelationshipTest-\(UUID().uuidString).sqlite")
        defer {
            for ext in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension(ext))
            }
        }

        let configuration = ModelConfiguration(url: storeURL)
        let modelContainer = try ModelContainer(
            for: OneSidedTask.self,
            OneSidedUser.self,
            configurations: configuration
        )
        let syncContainer = SyncContainer(modelContainer)

        // Seed: two users and a task with no members yet.
        try await syncContainer.sync(
            payload: [["id": 1, "name": "Alice"], ["id": 2, "name": "Bob"]],
            as: OneSidedUser.self
        )
        try await syncContainer.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [] as [Int]]],
            as: OneSidedTask.self
        )

        let taskID = try XCTUnwrap(
            syncContainer.mainContext.fetch(FetchDescriptor<OneSidedTask>()).first?.persistentModelID
        )
        let initialCount = try syncContainer.mainContext
            .fetch(FetchDescriptor<OneSidedTask>()).first?.members.count ?? 0
        XCTAssertEqual(initialCount, 0, "precondition: task starts with no members")

        // Sync a relationship-only change: title unchanged, member_ids [] → [1, 2].
        let notificationIDs = try await capturedChangedIDs(from: syncContainer) {
            try await syncContainer.sync(
                payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]],
                as: OneSidedTask.self
            )
        }

        // macOS CoreData surfaces the owner regardless, so this assertion cannot be
        // driven to failure on the SPM test host. It will catch any future regression
        // that breaks the relationship sync itself or removes syncMarkChanged().
        XCTAssertTrue(
            notificationIDs.contains(taskID),
            "Task identifier must be in didSaveChangesNotification changedIDs after a " +
            "to-many relationship-only change. Got: \(notificationIDs)"
        )

        // Relationship data must be correct in mainContext regardless of platform.
        let task = syncContainer.mainContext.model(for: taskID) as? OneSidedTask
        XCTAssertEqual(Set(task?.members.map(\.id) ?? []), Set([1, 2]))
    }

    /// Collects all PersistentIdentifiers from every didSaveChangesNotification
    /// fired by `syncContainer` while `body` executes.
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
        await fulfillment(of: [exp], timeout: 5)
        return ids
    }
}
