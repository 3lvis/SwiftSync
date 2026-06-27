import Observation
import SwiftData
import XCTest

@testable import SwiftSync

@Model
final class MissingInverseRegressionTag {
    @Attribute(.unique) var id: Int
    var name: String
    // Intentionally no explicit inverse — reproduces the Demo bug; don't "fix" it.
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
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try SwiftSync.syncApplyToManyForeignKeys(
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
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try SwiftSync.syncApplyToManyForeignKeys(
            self,
            relationship: \ExplicitInverseRegressionTask.tags,
            payload: payload,
            keys: ["tag_ids"],
            in: context,
            operations: operations
        )
    }
}

// One-sided to-many (User has no back-reference) — the pattern that triggers SwiftData's
// dirty-tracking gap on iOS persistent stores.
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
    var syncChangeToken: Int

    // No explicit inverse, mirroring Task.reviewers / Task.watchers in the Demo.
    @Relationship var members: [OneSidedUser]

    init(id: Int, title: String, syncChangeToken: Int = 0, members: [OneSidedUser] = []) {
        self.id = id
        self.title = title
        self.syncChangeToken = syncChangeToken
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
            if name != incoming {
                name = incoming
                changed = true
            }
        }
        return changed
    }
}

extension OneSidedTask: SyncUpdatableModel {
    // Spy counter incremented by syncMarkChanged(); nonisolated(unsafe) as test code mutates it unisolated.
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
            if title != incoming {
                title = incoming
                changed = true
            }
        }
        return changed
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try SwiftSync.syncApplyToManyForeignKeys(
            self,
            relationship: \OneSidedTask.members,
            payload: payload,
            keys: ["member_ids"],
            in: context,
            operations: operations
        )
    }

    func syncMarkChanged() {
        syncChangeToken += 1
        OneSidedTask.syncMarkChangedCallCount += 1
    }
}

@Model
final class OneSidedNestedUser {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class OneSidedNestedTask {
    @Attribute(.unique) var id: Int
    var title: String

    @Relationship var members: [OneSidedNestedUser]

    init(id: Int, title: String, members: [OneSidedNestedUser] = []) {
        self.id = id
        self.title = title
        self.members = members
    }
}

extension OneSidedNestedUser: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<OneSidedNestedUser, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OneSidedNestedUser {
        OneSidedNestedUser(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incoming: String = try payload.required(String.self, for: "name")
            if name != incoming {
                name = incoming
                changed = true
            }
        }
        return changed
    }
}

extension OneSidedNestedTask: SyncUpdatableModel {
    nonisolated(unsafe) static var syncMarkChangedCallCount: Int = 0

    typealias SyncID = Int
    static var syncIdentity: KeyPath<OneSidedNestedTask, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OneSidedNestedTask {
        OneSidedNestedTask(
            id: try payload.required(Int.self, for: "id"),
            title: try payload.required(String.self, for: "title")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("title") {
            let incoming: String = try payload.required(String.self, for: "title")
            if title != incoming {
                title = incoming
                changed = true
            }
        }
        return changed
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try SwiftSync.syncApplyToManyNestedObjects(
            self,
            relationship: \OneSidedNestedTask.members,
            payload: payload,
            keys: ["members"],
            in: context,
            operations: operations
        )
    }

    func syncMarkChanged() {
        OneSidedNestedTask.syncMarkChangedCallCount += 1
    }
}

/// Spy-based so the contract is testable on macOS — notification behavior differs per platform.
final class SyncMarkChangedCallSiteTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OneSidedTask.syncMarkChangedCallCount = 0
    }

    func testSyncApplyToManyForeignKeysCallsSyncMarkChangedAfterMembershipChange() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedTask.self, OneSidedUser.self,
            configurations: config
        )
        let context = ModelContext(container)

        try await context.sync(
            payload: [["id": 1, "name": "Alice"], ["id": 2, "name": "Bob"]], as: OneSidedUser.self)
        try await context.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [] as [Int]]], as: OneSidedTask.self)

        let task = try XCTUnwrap(context.fetch(FetchDescriptor<OneSidedTask>()).first)
        XCTAssertEqual(task.members.count, 0, "precondition: task starts with no members")

        OneSidedTask.syncMarkChangedCallCount = 0

        // Membership change [] → [1, 2] with title unchanged, so only the relationship triggers the mark.
        try await context.sync(payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]], as: OneSidedTask.self)

        XCTAssertEqual(
            OneSidedTask.syncMarkChangedCallCount, 1,
            "syncApplyToManyForeignKeys must call syncMarkChanged() after a membership change "
                + "so the owning model's store row is marked dirty on iOS persistent stores. "
                + "Count was \(OneSidedTask.syncMarkChangedCallCount), expected 1."
        )

        XCTAssertEqual(Set(task.members.map(\.id)), Set([1, 2]))
    }

    func testSyncApplyToManyForeignKeysDoesNotCallSyncMarkChangedWhenUnchanged() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedTask.self, OneSidedUser.self,
            configurations: config
        )
        let context = ModelContext(container)

        try await context.sync(
            payload: [["id": 1, "name": "Alice"], ["id": 2, "name": "Bob"]], as: OneSidedUser.self)
        try await context.sync(payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]], as: OneSidedTask.self)

        OneSidedTask.syncMarkChangedCallCount = 0

        try await context.sync(payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]], as: OneSidedTask.self)

        XCTAssertEqual(
            OneSidedTask.syncMarkChangedCallCount, 0,
            "syncMarkChanged() must not be called when relationship membership is unchanged."
        )
    }

    func testSyncApplyToManyNestedObjectsCallsSyncMarkChangedAfterMembershipChange() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedNestedTask.self, OneSidedNestedUser.self,
            configurations: config
        )
        let context = ModelContext(container)

        try await context.sync(
            payload: [["id": 10, "title": "Task 10", "members": [] as [[String: Any]]]], as: OneSidedNestedTask.self)

        let task = try XCTUnwrap(context.fetch(FetchDescriptor<OneSidedNestedTask>()).first)
        XCTAssertEqual(task.members.count, 0, "precondition: task starts with no members")

        OneSidedNestedTask.syncMarkChangedCallCount = 0

        try await context.sync(
            payload: [
                [
                    "id": 10,
                    "title": "Task 10",
                    "members": [
                        ["id": 1, "name": "Alice"],
                        ["id": 2, "name": "Bob"],
                    ],
                ]
            ], as: OneSidedNestedTask.self)

        XCTAssertEqual(
            OneSidedNestedTask.syncMarkChangedCallCount, 1,
            "syncApplyToManyNestedObjects must call syncMarkChanged() after a membership change."
        )
        XCTAssertEqual(Set(task.members.map(\.id)), Set([1, 2]))
    }

    func testSyncApplyToManyNestedObjectsDoesNotCallSyncMarkChangedWhenUnchanged() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedNestedTask.self, OneSidedNestedUser.self,
            configurations: config
        )
        let context = ModelContext(container)

        try await context.sync(
            payload: [
                [
                    "id": 10,
                    "title": "Task 10",
                    "members": [
                        ["id": 1, "name": "Alice"],
                        ["id": 2, "name": "Bob"],
                    ],
                ]
            ], as: OneSidedNestedTask.self)

        OneSidedNestedTask.syncMarkChangedCallCount = 0

        try await context.sync(
            payload: [
                [
                    "id": 10,
                    "title": "Task 10",
                    "members": [
                        ["id": 1, "name": "Alice"],
                        ["id": 2, "name": "Bob"],
                    ],
                ]
            ], as: OneSidedNestedTask.self)

        XCTAssertEqual(
            OneSidedNestedTask.syncMarkChangedCallCount, 0,
            "syncMarkChanged() must not be called when nested relationship membership is unchanged."
        )
    }

    func testSyncApplyToManyNestedObjectsCallsSyncMarkChangedAfterClear() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedNestedTask.self, OneSidedNestedUser.self,
            configurations: config
        )
        let context = ModelContext(container)

        try await context.sync(
            payload: [
                [
                    "id": 10,
                    "title": "Task 10",
                    "members": [
                        ["id": 1, "name": "Alice"],
                        ["id": 2, "name": "Bob"],
                    ],
                ]
            ], as: OneSidedNestedTask.self)

        let task = try XCTUnwrap(context.fetch(FetchDescriptor<OneSidedNestedTask>()).first)
        XCTAssertEqual(Set(task.members.map(\.id)), Set([1, 2]), "precondition: task starts populated")

        OneSidedNestedTask.syncMarkChangedCallCount = 0

        try await context.sync(
            payload: [
                [
                    "id": 10,
                    "title": "Task 10",
                    "members": NSNull(),
                ]
            ], as: OneSidedNestedTask.self)

        XCTAssertEqual(
            OneSidedNestedTask.syncMarkChangedCallCount, 1,
            "syncApplyToManyNestedObjects must call syncMarkChanged() after an explicit clear."
        )
        XCTAssertEqual(task.members.count, 0)
    }

    @MainActor
    func testSyncMarkChangedTokenMakesDirectModelObservationSeeToManyMembershipChange() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OneSidedTask.self, OneSidedUser.self,
            configurations: config
        )
        let context = ModelContext(container)

        try await context.sync(
            payload: [["id": 1, "name": "Alice"], ["id": 2, "name": "Bob"], ["id": 3, "name": "Cara"]],
            as: OneSidedUser.self)
        try await context.sync(payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]], as: OneSidedTask.self)

        let task = try XCTUnwrap(context.fetch(FetchDescriptor<OneSidedTask>()).first)
        XCTAssertEqual(task.members.map(\.id).sorted(), [1, 2])

        // onChange fires synchronously during the mutation, so the flag is set by the time the sync's
        // await returns — asserting it directly avoids the polling/re-registration that flakes under load.
        let observedChange = ObservationFlag()
        withObservationTracking {
            _ = task.members.map(\.id).sorted()
        } onChange: {
            observedChange.fire()
        }

        try await context.sync(payload: [["id": 10, "title": "Task 10", "member_ids": [2, 3]]], as: OneSidedTask.self)

        XCTAssertEqual(task.members.map(\.id).sorted(), [2, 3])
        XCTAssertTrue(
            observedChange.didFire,
            "direct withObservationTracking observer was not notified of the to-many membership change"
        )
    }
}

/// `onChange` is `@Sendable` and may fire off the main actor, so the flag guards its state with a lock.
private final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() {
        lock.lock()
        fired = true
        lock.unlock()
    }

    var didFire: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
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

        try await context.sync(
            payload: [
                ["id": 1, "name": "Tag 1"],
                ["id": 2, "name": "Tag 2"],
                ["id": 3, "name": "Tag 3"],
            ], as: MissingInverseRegressionTag.self)

        // Repro needs the demo ordering: a single-task sync first…
        try await context.sync(
            payload: [
                [
                    "id": 10,
                    "title": "Task 10",
                    "tag_ids": [1, 2],
                ]
            ], as: MissingInverseRegressionTask.self)

        // …then a batch sync whose second task shares tag 2 — the membership the bug drops.
        try await context.sync(
            payload: [
                ["id": 10, "title": "Task 10", "tag_ids": [1, 2]],
                ["id": 20, "title": "Task 20", "tag_ids": [2, 3]],
            ], as: MissingInverseRegressionTask.self)

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

        try await context.sync(
            payload: [
                ["id": 1, "name": "Tag 1"],
                ["id": 2, "name": "Tag 2"],
                ["id": 3, "name": "Tag 3"],
            ], as: ExplicitInverseRegressionTag.self)

        try await context.sync(
            payload: [
                [
                    "id": 10,
                    "title": "Task 10",
                    "tag_ids": [1, 2],
                ]
            ], as: ExplicitInverseRegressionTask.self)

        try await context.sync(
            payload: [
                ["id": 10, "title": "Task 10", "tag_ids": [1, 2]],
                ["id": 20, "title": "Task 20", "tag_ids": [2, 3]],
            ], as: ExplicitInverseRegressionTask.self)

        let tasks = try context.fetch(FetchDescriptor<ExplicitInverseRegressionTask>())
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, Set($0.tags.map(\.id))) })

        XCTAssertEqual(tasksByID[10], Set([1, 2]))
        XCTAssertEqual(tasksByID[20], Set([2, 3]))
    }
}
