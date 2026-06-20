import SwiftData
import XCTest

@testable import SwiftSync

private struct EngineTestError: Error, Equatable { let id: String }

/// Confirms everything (no failures) and records the batches it was handed.
private actor ConfirmingBackend: SyncBackend {
    private(set) var batches: [SyncPendingChanges] = []
    func push(_ pending: SyncPendingChanges) async throws -> [SyncPushFailure] {
        batches.append(pending)
        return []
    }
}

/// Rejects one id, confirms the rest.
private struct RejectingBackend: SyncBackend {
    let rejectID: String
    func push(_ pending: SyncPendingChanges) async throws -> [SyncPushFailure] {
        [SyncPushFailure(id: rejectID, error: EngineTestError(id: rejectID))]
    }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    private func makeEngine(isOnline: Bool = true) throws -> SyncEngine {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let container = try SyncContainer(
            for: PushNote.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("store.sqlite")))
        return SyncEngine(container, isOnline: isOnline)
    }

    private func insert(_ id: String, in engine: SyncEngine) throws {
        engine.container.mainContext.insert(PushNote(id: id, title: id))
        try engine.container.mainContext.save()
    }

    /// A drain pushes every pending row through the registered backend and clears the queue.
    func testDrainPushesPendingThroughBackendAndClears() async throws {
        let engine = try makeEngine()
        let backend = ConfirmingBackend()
        engine.register(backend, for: PushNote.self)
        try insert("n1", in: engine)

        await engine.drain()

        let batches = await backend.batches
        XCTAssertEqual(batches.first?.inserts, ["n1"])
        XCTAssertTrue(try SwiftSync.pendingChanges(for: PushNote.self, in: engine.container.mainContext).isEmpty)
        XCTAssertEqual(engine.pendingCount, 0)
    }

    /// While offline, a drain does nothing — the backend is never called and the change stays pending.
    func testOfflineDrainIsNoOp() async throws {
        let engine = try makeEngine(isOnline: false)
        let backend = ConfirmingBackend()
        engine.register(backend, for: PushNote.self)
        try insert("n1", in: engine)

        await engine.drain()

        let batches = await backend.batches
        XCTAssertTrue(batches.isEmpty, "offline drain must not call the backend")
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: engine.container.mainContext).inserts, ["n1"])
    }

    /// Flipping offline→online drains the queue automatically (no manual push call).
    func testReconnectAutoDrains() async throws {
        let engine = try makeEngine(isOnline: false)
        let backend = ConfirmingBackend()
        engine.register(backend, for: PushNote.self)
        try insert("n1", in: engine)

        engine.isOnline = true
        await engine.inFlightDrain?.value

        let batches = await backend.batches
        XCTAssertEqual(batches.first?.inserts, ["n1"])
        XCTAssertTrue(try SwiftSync.pendingChanges(for: PushNote.self, in: engine.container.mainContext).isEmpty)
    }

    /// After a drain with a rejection, `failures` carries the rejected row and the counts split it out of
    /// pending (a failed row reads as failed, not pending).
    func testFailuresAndCountsAfterDrain() async throws {
        let engine = try makeEngine()
        engine.register(RejectingBackend(rejectID: "n2"), for: PushNote.self)
        try insert("n1", in: engine)
        try insert("n2", in: engine)

        await engine.drain()

        XCTAssertEqual(engine.failures.map(\.id), ["n2"])
        XCTAssertEqual(engine.failedCount, 1)
        // Both stay pending (any failure freezes the token), but the failed one isn't double-counted.
        XCTAssertEqual(engine.pendingCount, 1, "2 pending − 1 surfaced as failed = 1 pending")
    }
}
