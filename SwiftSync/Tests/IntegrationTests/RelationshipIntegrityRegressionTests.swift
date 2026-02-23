import XCTest
import SwiftData
import SwiftSync

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

extension MissingInverseRegressionTask: SyncRelationshipUpdatableModel {
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

extension ExplicitInverseRegressionTask: SyncRelationshipUpdatableModel {
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
}
