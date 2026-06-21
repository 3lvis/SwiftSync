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

/// Throws — a transport/server error, *not* a per-row rejection.
private struct ThrowingBackend: SyncBackend {
    struct PushError: Error {}
    func push(_ pending: SyncPendingChanges) async throws -> [SyncPushFailure] { throw PushError() }
}

@MainActor
final class SyncContainerOutboundTests: XCTestCase {
    private func makeContainer(isOnline: Bool = true) throws -> SyncContainer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbound-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let container = try SyncContainer(
            for: PushNote.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("store.sqlite")))
        container.isOnline = isOnline
        return container
    }

    private func insert(_ id: String, in container: SyncContainer) throws {
        container.mainContext.insert(PushNote(id: id, title: id))
        try container.mainContext.save()
    }

    /// A drain pushes every pending row through the registered backend and clears the queue.
    func testDrainPushesPendingThroughBackendAndClears() async throws {
        let container = try makeContainer()
        let backend = ConfirmingBackend()
        container.register(backend, for: PushNote.self)
        try insert("n1", in: container)

        let failures = try await container.drain()

        let batches = await backend.batches
        XCTAssertEqual(batches.first?.inserts, ["n1"])
        XCTAssertEqual(failures?.isEmpty, true, "completed clean: an empty (non-nil) result")
        XCTAssertTrue(try SwiftSync.pendingChanges(for: PushNote.self, in: container.mainContext).isEmpty)
    }

    /// While offline, a drain does nothing — the backend is never called and the change stays pending.
    func testOfflineDrainIsNoOp() async throws {
        let container = try makeContainer(isOnline: false)
        let backend = ConfirmingBackend()
        container.register(backend, for: PushNote.self)
        try insert("n1", in: container)

        let result = try await container.drain()

        XCTAssertNil(result, "a skipped (offline) drain returns nil, not a clean empty result")
        let batches = await backend.batches
        XCTAssertTrue(batches.isEmpty, "offline drain must not call the backend")
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: container.mainContext).inserts, ["n1"])
    }

    /// Flipping offline→online drains the queue automatically and reports the result to `onDrainComplete`.
    func testReconnectAutoDrainsAndReportsResult() async throws {
        let container = try makeContainer(isOnline: false)
        let backend = ConfirmingBackend()
        container.register(backend, for: PushNote.self)
        try insert("n1", in: container)

        var reported: [SyncPushFailure]?
        container.onDrainComplete = { reported = $0 }

        container.isOnline = true
        await container.inFlightDrain?.value

        let batches = await backend.batches
        XCTAssertEqual(batches.first?.inserts, ["n1"])
        XCTAssertEqual(reported?.isEmpty, true, "onDrainComplete fires after a reconnect drain")
        XCTAssertTrue(try SwiftSync.pendingChanges(for: PushNote.self, in: container.mainContext).isEmpty)
    }

    /// A rejection comes back from `drain()` verbatim; the row stays pending (token frozen).
    func testDrainReturnsRejections() async throws {
        let container = try makeContainer()
        container.register(RejectingBackend(rejectID: "n2"), for: PushNote.self)
        try insert("n1", in: container)
        try insert("n2", in: container)

        let failures = try await container.drain()

        XCTAssertEqual(failures?.map(\.id), ["n2"])
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: container.mainContext).inserts.sorted(),
            ["n1", "n2"], "any failure freezes the token, so both stay pending")
    }

    /// A backend that throws (transport/server error) must surface as a thrown drain — never a clean
    /// empty result that the app would mistake for "all synced" and use to wipe its failures inbox.
    func testDrainThrowsOnBackendErrorRatherThanReportingClean() async throws {
        let container = try makeContainer()
        container.register(ThrowingBackend(), for: PushNote.self)
        try insert("n1", in: container)

        do {
            _ = try await container.drain()
            XCTFail("a throwing backend must surface as a thrown drain, not a clean/empty result")
        } catch is ThrowingBackend.PushError {
            // expected
        }
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: container.mainContext).inserts, ["n1"],
            "a failed drain advances nothing — the row stays pending")
    }

    /// A failed reconnect drain must not fire `onDrainComplete` (which would report a clean result and let
    /// the app clear its inbox); the rows stay pending and retry.
    func testReconnectDoesNotReportWhenBackendThrows() async throws {
        let container = try makeContainer(isOnline: false)
        container.register(ThrowingBackend(), for: PushNote.self)
        try insert("n1", in: container)

        var reportCount = 0
        container.onDrainComplete = { _ in reportCount += 1 }

        container.isOnline = true
        await container.inFlightDrain?.value

        XCTAssertEqual(reportCount, 0, "a failed reconnect drain must not report a (clean) result")
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: container.mainContext).inserts, ["n1"])
    }
}
