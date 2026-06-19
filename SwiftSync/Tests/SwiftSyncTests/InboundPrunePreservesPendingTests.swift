import SwiftData
import XCTest

@testable import SwiftSync

// Both inbound-syncable (`SyncUpdatableModel`) and offline-pushable (`SyncOfflineModel`) under a
// parent — the shape that exposes the inbound-pull / outbound-queue collision these tests guard.
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
        // A local-only insert the server has never seen (offline-created, rejected on push).
        context.insert(PruneTask(id: "t-local", title: "offline created", remoteID: nil, project: project))
        try context.save()

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
    func testParentScopedPullStillPrunesSyncedServerDeletedRow() async throws {
        let container = try ModelContainer(
            for: PruneProject.self, PruneTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let project = PruneProject(id: "p1")
        context.insert(project)
        // A row the server knows about (`remoteID` set) that the server then omits → genuinely deleted
        // server-side, so the prune must still remove it.
        context.insert(
            PruneTask(id: "t-synced", title: "synced", remoteID: "r1", project: project))
        try context.save()

        try await SwiftSync.sync(
            payload: [], as: PruneTask.self, in: context, parent: project,
            relationship: \PruneTask.project)

        let ids = Set(try context.fetch(FetchDescriptor<PruneTask>()).map(\.id))
        XCTAssertFalse(ids.contains("t-synced"), "a server-known row the server deleted must be pruned")
    }
}
