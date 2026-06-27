import SwiftData
import XCTest

@testable import SwiftSync

@Model
final class PruneProject {
    @Attribute(.unique) var id: String
    @Relationship(deleteRule: .cascade, inverse: \PruneTask.project) var tasks: [PruneTask]

    init(id: String, tasks: [PruneTask] = []) {
        self.id = id
        self.tasks = tasks
    }
}

@Syncable
@Model
final class PruneTask {
    // .preserveValueOnDeletion is the offline opt-in: it gives this model dirty-set pull semantics.
    @Attribute(.unique, .preserveValueOnDeletion) var id: String
    var title: String
    @NotExport var project: PruneProject?

    init(id: String, title: String, project: PruneProject? = nil) {
        self.id = id
        self.title = title
        self.project = project
    }
}

/// An inbound pull preserves a never-pushed local insert (it's in the history dirty-set) but still
/// prunes a server-deleted row (which arrived via a pull and so isn't dirty).
@MainActor
final class InboundPrunePreservesPendingTests: XCTestCase {
    private func makeContainer() throws -> SyncContainer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbound-prune-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try SyncContainer(
            for: PruneProject.self, PruneTask.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("store.sqlite")))
    }

    func testParentScopedPullKeepsNeverSyncedLocalInsert() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let project = PruneProject(id: "p1")
        context.insert(project)
        context.insert(PruneTask(id: "t-local", title: "offline created", project: project))
        try context.save()

        try await container.sync(
            payload: [["id": "t-server", "title": "from server"]],
            as: PruneTask.self, parent: project, relationship: \PruneTask.project)

        let ids = Set(try context.fetch(FetchDescriptor<PruneTask>()).map(\.id))
        XCTAssertTrue(ids.contains("t-local"), "a never-synced local insert must survive a pull that omits it")
        XCTAssertTrue(ids.contains("t-server"))
    }

    func testParentScopedPullStillPrunesSyncedServerDeletedRow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let project = PruneProject(id: "p1")
        context.insert(project)
        try context.save()

        // Arrives via a pull, so it's server-known and not dirty…
        try await container.sync(
            payload: [["id": "t-synced", "title": "synced"]],
            as: PruneTask.self, parent: project, relationship: \PruneTask.project)
        // …then an empty pull omits it, meaning server-side deletion, so the prune must remove it.
        try await container.sync(
            payload: [], as: PruneTask.self, parent: project, relationship: \PruneTask.project)

        let ids = Set(try context.fetch(FetchDescriptor<PruneTask>()).map(\.id))
        XCTAssertFalse(ids.contains("t-synced"), "a server-known row the server deleted must be pruned")
    }
}
