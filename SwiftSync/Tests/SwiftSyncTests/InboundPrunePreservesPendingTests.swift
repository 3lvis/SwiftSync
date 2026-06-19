import SwiftData
import XCTest

@testable import SwiftSync

// A model that is both inbound-syncable (`SyncUpdatableModel`) and offline-pushable
// (`SyncOfflineModel`), scoped under a parent — the exact shape that exposes the inbound-pull /
// outbound-queue collision: a full-set pull's `delete-missing` pass must not delete rows that have
// un-acknowledged local changes.
@Model
final class PruneProject {
    @Attribute(.unique) var id: String
    var tasks: [PruneTask]

    init(id: String, tasks: [PruneTask] = []) {
        self.id = id
        self.tasks = tasks
    }
}

@Model
final class PruneTask {
    @Attribute(.unique) var id: String
    var title: String
    var remoteID: String?
    var updatedAt: Date
    var locallyDeleted: Bool
    var failureReason: String?
    @Relationship(inverse: \PruneProject.tasks) var project: PruneProject?

    init(
        id: String, title: String, remoteID: String? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 0), locallyDeleted: Bool = false,
        project: PruneProject? = nil
    ) {
        self.id = id
        self.title = title
        self.remoteID = remoteID
        self.updatedAt = updatedAt
        self.locallyDeleted = locallyDeleted
        self.failureReason = nil
        self.project = project
    }
}

extension PruneTask: SyncUpdatableModel {
    typealias SyncID = String
    static var syncIdentity: KeyPath<PruneTask, String> { \.id }

    static func make(from payload: SyncPayload) throws -> PruneTask {
        PruneTask(
            id: try payload.required(String.self, for: "id"),
            title: try payload.required(String.self, for: "title"))
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        let incomingTitle = try payload.required(String.self, for: "title")
        guard title != incomingTitle else { return false }
        title = incomingTitle
        return true
    }
}

extension PruneTask: SyncOfflineModel {
    var syncLocalID: String { id }
    var syncRemoteID: String? {
        get { remoteID }
        set { remoteID = newValue }
    }
    var syncUpdatedAt: Date { updatedAt }
    var syncIsDeleted: Bool { locallyDeleted }
    var syncFailureReason: String? {
        get { failureReason }
        set { failureReason = newValue }
    }
}

final class InboundPrunePreservesPendingTests: XCTestCase {
    @MainActor
    func testParentScopedPullKeepsNeverSyncedLocalInsert() async throws {
        let container = try ModelContainer(
            for: PruneProject.self, PruneTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let project = PruneProject(id: "p1")
        context.insert(project)
        context.insert(PruneTask(id: "t-server", title: "from server", remoteID: "r1", project: project))
        // A local-only insert the server has never seen (e.g. created offline, rejected on push).
        context.insert(PruneTask(id: "t-local", title: "offline created", remoteID: nil, project: project))
        try context.save()

        // Pull the project's authoritative task set — it omits the local-only row.
        try await SwiftSync.sync(
            payload: [["id": "t-server", "title": "from server"]],
            as: PruneTask.self, in: context, parent: project, relationship: \PruneTask.project)

        let ids = Set(try context.fetch(FetchDescriptor<PruneTask>()).map(\.id))
        XCTAssertTrue(
            ids.contains("t-local"),
            "a never-synced local insert must survive an inbound pull that omits it")
        XCTAssertTrue(ids.contains("t-server"))
    }

    @MainActor
    func testParentScopedPullKeepsLocallyEditedRowWhenCursorGiven() async throws {
        let container = try ModelContainer(
            for: PruneProject.self, PruneTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let cursor = Date(timeIntervalSince1970: 1_000)
        let project = PruneProject(id: "p1")
        context.insert(project)
        // A synced row with a local edit *after* the cursor — a pending update not yet pushed.
        context.insert(
            PruneTask(
                id: "t-edited", title: "local edit", remoteID: "r1",
                updatedAt: Date(timeIntervalSince1970: 2_000), project: project))
        try context.save()

        // The server's set omits it (e.g. deleted server-side). The local edit must win, not vanish.
        try await SwiftSync.sync(
            payload: [], as: PruneTask.self, in: context, parent: project,
            relationship: \PruneTask.project, pendingChangesSince: cursor)

        let ids = Set(try context.fetch(FetchDescriptor<PruneTask>()).map(\.id))
        XCTAssertTrue(ids.contains("t-edited"), "a row edited after the cursor must survive the prune")
    }

    @MainActor
    func testParentScopedPullStillPrunesCleanServerDeletedRow() async throws {
        let container = try ModelContainer(
            for: PruneProject.self, PruneTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let cursor = Date(timeIntervalSince1970: 1_000)
        let project = PruneProject(id: "p1")
        context.insert(project)
        // A fully-synced, locally-untouched row (updated before the cursor). Server omits it → it was
        // genuinely deleted server-side, so the prune must still remove it.
        context.insert(
            PruneTask(
                id: "t-clean", title: "clean", remoteID: "r1",
                updatedAt: Date(timeIntervalSince1970: 500), project: project))
        try context.save()

        try await SwiftSync.sync(
            payload: [], as: PruneTask.self, in: context, parent: project,
            relationship: \PruneTask.project, pendingChangesSince: cursor)

        let ids = Set(try context.fetch(FetchDescriptor<PruneTask>()).map(\.id))
        XCTAssertFalse(ids.contains("t-clean"), "a clean, server-deleted row must still be pruned")
    }
}
