import DemoBackend
import SwiftData
import SwiftSync
import XCTest

@testable import DemoCore

final class ConvergingDrainTests: XCTestCase {

    /// P1 strand: an edit that lands *after* a drain reads its pending snapshot but *before* that drain
    /// finishes must still reach the server. A coalescing drain covers only its original snapshot and
    /// never re-reads, so the late edit is stranded; a converging drain re-reads until pending is empty.
    ///
    /// Deterministic by construction: the drain is driven with an explicit handle (no reconnect `didSet`),
    /// only the first upload parks, and convergence's later uploads flow through — so the test never
    /// assumes how many uploads a correct drain performs.
    @MainActor
    func testLateEditDuringDrainReachesServer() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed, networkDelayMode: .disabled)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
        try await engine.syncProjectTasks(projectID: projectID)

        // A local pending insert (online, so no reconnect drain fires): clone a valid seeded task so the
        // server accepts the upsert, then drop it into the store as a default-author (local) edit.
        let template = try XCTUnwrap(
            fetchTask(id: DemoSeedData.SeedIDs.Tasks.sessionTimeout, in: syncContainer.mainContext))
        let row = Task(
            id: "CONVERGE-A",
            projectID: template.projectID,
            assigneeID: template.assigneeID,
            authorID: template.authorID,
            title: "v1",
            descriptionText: template.descriptionText,
            state: template.state,
            stateLabel: template.stateLabel,
            project: template.project
        )
        syncContainer.mainContext.insert(row)
        try syncContainer.mainContext.save()

        // Park only the first upload mid-flight; convergence's later uploads flow straight through, so the
        // test never assumes how many uploads a correct drain performs.
        nonisolated(unsafe) var uploadStarted: CheckedContinuation<Void, Never>?
        nonisolated(unsafe) var releaseGate: CheckedContinuation<Void, Never>?
        nonisolated(unsafe) var didPark = false
        apiClient.beforeUpload = {
            guard !didPark else { return }
            didPark = true
            await withCheckedContinuation { gate in
                releaseGate = gate
                uploadStarted?.resume()
            }
        }

        let drain = _Concurrency.Task { @MainActor in try await engine.pushPendingChanges() }
        await withCheckedContinuation { uploadStarted = $0 }  // drain has snapshotted {CONVERGE-A: v1} and parked its upload

        // The late edit: lands after the snapshot, while the upload is parked mid-flight. The demo server
        // stamps `updated_at` to its own clock when it writes the create's reviewer/watcher rows, so the
        // late edit must be unambiguously newer than that server clock to win LWW (and prove it landed).
        let pending = try XCTUnwrap(fetchTask(id: "CONVERGE-A", in: syncContainer.mainContext))
        pending.title = "v2"
        pending.updatedAt = Date().addingTimeInterval(3600)
        try syncContainer.mainContext.save()

        releaseGate?.resume()
        _ = try await drain.value

        let server = try await apiClient.getTaskDetail(taskID: "CONVERGE-A")
        XCTAssertEqual(
            server?.string("title"), "v2",
            "the edit that landed mid-drain must reach the server, not be stranded")
        XCTAssertEqual(engine.pendingChangeCount, 0, "convergence drains everything pending")
    }

    @MainActor
    private func makeSyncContainer() throws -> SyncContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try SyncContainer(
            for: Project.self,
            User.self,
            Task.self,
            Item.self,
            TaskStateOption.self,
            configurations: configuration
        )
    }

    @MainActor
    private func fetchTask(id: String, in context: ModelContext) throws -> Task? {
        try context.fetch(FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })).first
    }
}
