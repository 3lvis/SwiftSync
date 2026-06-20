import SwiftData
import XCTest

@testable import SwiftSync

@Syncable
@Model
final class PushNote {
    @Attribute(.unique, .preserveValueOnDeletion) var id: String
    var title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

private struct PushTestError: Error, Equatable, Sendable { let message: String }

@MainActor
final class OfflinePushTests: XCTestCase {
    private func makeContainer() throws -> SyncContainer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-push-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try SyncContainer(
            for: PushNote.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("store.sqlite")))
    }

    /// Confirm every pending id — the total-accounting verdict map for a fully-successful push.
    private func confirmAll(_ pending: SyncPendingChanges) -> [String: SyncRowOutcome] {
        Dictionary(
            uniqueKeysWithValues: (pending.inserts + pending.updates + pending.deletes).map { ($0, .confirmed) })
    }

    /// History-derived partitioning: after a baseline push makes some rows "synced" (behind the
    /// token), a fresh round of local edits partitions into insert/update/delete — and a row inserted
    /// *and* deleted before any push is dropped, since the server never saw it.
    func testPartitionsPendingChangesFromHistory() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        for id in ["a", "b", "d"] { context.insert(PushNote(id: id, title: id)) }
        try context.save()
        // Baseline push: a, b, d become synced (token advances past their inserts).
        _ = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context, process: confirmAll)

        try mutate(context) { $0.first { $0.id == "b" }?.title = "edited" }  // update
        try delete("d", in: context)  // delete
        context.insert(PushNote(id: "c", title: "new"))  // insert
        let e = PushNote(id: "e", title: "ephemeral")  // insert-then-delete → dropped
        context.insert(e)
        try context.save()
        context.delete(e)
        try context.save()

        let pending = try SwiftSync.pendingChanges(for: PushNote.self, in: context)
        XCTAssertEqual(pending.inserts.sorted(), ["c"])
        XCTAssertEqual(pending.updates.sorted(), ["b"])
        XCTAssertEqual(pending.deletes.sorted(), ["d"])
    }

    /// A fully-acknowledged push advances the token, so nothing is left pending afterwards.
    func testFullyAcknowledgedPushClearsPending() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "c1", title: "insert"))
        try context.save()

        let failures = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { pending in
            XCTAssertEqual(pending.inserts, ["c1"])
            return ["c1": .confirmed]
        }

        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(try SwiftSync.pendingChanges(for: PushNote.self, in: context).isEmpty)
    }

    /// Pure-bubble: a rejected row's error is returned verbatim and nothing is written to the store, so
    /// the row stays pending (the token does not advance) and is re-detected next push.
    func testRejectedInsertBubblesAndStaysPending() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "c1", title: "rejected"))
        try context.save()

        let failures = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { _ in
            ["c1": .rejected(PushTestError(message: "422"))]
        }

        XCTAssertEqual(failures.first?.id, "c1")
        XCTAssertEqual(failures.first?.error as? PushTestError, PushTestError(message: "422"))
        XCTAssertEqual(try SwiftSync.pendingChanges(for: PushNote.self, in: context).inserts, ["c1"])
    }

    /// An unacknowledged change must not advance the token, or it would silently fall out of detection.
    func testUnacknowledgedPushKeepsChangePending() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "u1", title: "v1"))
        try context.save()
        _ = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context, process: confirmAll)  // synced

        try mutate(context) { $0.first { $0.id == "u1" }?.title = "v2" }
        try context.save()

        _ = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { _ in
            ["u1": .rejected(PushTestError(message: "500"))]
        }
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: context).updates, ["u1"],
            "an unacknowledged update stays pending")
    }

    /// Any failure freezes the token (all-or-nothing): the rejected row comes back in the returned
    /// failures, and even the row the server accepted stays pending and is re-detected next push
    /// (at-least-once).
    func testPartialFailureFreezesTheTokenForTheWholeBatch() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "c1", title: "ok"))
        context.insert(PushNote(id: "c2", title: "rejected"))
        try context.save()

        let failures = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { _ in
            ["c1": .confirmed, "c2": .rejected(PushTestError(message: "422"))]
        }
        XCTAssertEqual(failures.map(\.id), ["c2"])
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: context).inserts.sorted(), ["c1", "c2"],
            "a failure freezes the token, so even the accepted row is re-detected")
    }

    /// Total accounting: the verdict map must cover every pending id. Omitting one would confirm it by
    /// omission (silent data loss), so the push throws `.incompletePushAccounting` and advances nothing —
    /// both rows stay pending.
    func testOmittingAPendingIDThrowsAndAdvancesNothing() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "c1", title: "reported"))
        context.insert(PushNote(id: "c2", title: "forgotten"))
        try context.save()

        do {
            _ = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { _ in
                ["c1": .confirmed]  // c2 omitted
            }
            XCTFail("expected withPendingChanges to throw when a pending id has no outcome")
        } catch let error as SyncError {
            guard case .incompletePushAccounting(let unaccounted, let unexpected) = error else {
                return XCTFail("expected .incompletePushAccounting, got \(error)")
            }
            XCTAssertEqual(unaccounted, ["c2"])
            XCTAssertTrue(unexpected.isEmpty)
        }

        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: context).inserts.sorted(), ["c1", "c2"],
            "an incomplete-accounting push must advance nothing")
    }

    /// A verdict for an id that isn't in the batch is a consumer bug — the push throws rather than
    /// silently ignoring it.
    func testReportingAnIDNotInTheBatchThrows() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "c1", title: "real"))
        try context.save()

        do {
            _ = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { _ in
                ["c1": .confirmed, "ghost": .confirmed]
            }
            XCTFail("expected withPendingChanges to throw for an id not in the batch")
        } catch let error as SyncError {
            guard case .incompletePushAccounting(let unaccounted, let unexpected) = error else {
                return XCTFail("expected .incompletePushAccounting, got \(error)")
            }
            XCTAssertTrue(unaccounted.isEmpty)
            XCTAssertEqual(unexpected, ["ghost"])
        }
    }

    /// A local write during the upload await wasn't in the batch, so the token must not advance past it:
    /// it stays pending rather than being silently swallowed.
    func testLocalWriteDuringUploadStaysPending() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "p1", title: "first"))
        try context.save()

        let failures = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { pending in
            XCTAssertEqual(pending.inserts, ["p1"])
            // A new local row appears after the batch was captured, while "uploading".
            context.insert(PushNote(id: "p2", title: "during upload"))
            try context.save()
            return ["p1": .confirmed]
        }

        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: context).inserts, ["p2"],
            "a local write during upload must survive the token advance")
    }

    /// Push must fail before uploading when the bookkeeping model is missing, so an acknowledged server
    /// write is never stranded by a token write that throws afterward.
    func testPushFailsBeforeUploadingWhenBookkeepingModelMissing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-bookkeeping-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // Built WITHOUT SyncContainer → PushHistoryTokenRecord is absent from the schema.
        let container = try ModelContainer(
            for: PushNote.self,
            configurations: ModelConfiguration(url: directory.appendingPathComponent("store.sqlite")))
        let context = ModelContext(container)
        context.insert(PushNote(id: "x", title: "t"))
        try context.save()

        var uploadCalled = false
        do {
            _ = try await SwiftSync.withPendingChanges(for: PushNote.self, in: context) { _ in
                uploadCalled = true
                return [:]
            }
            XCTFail("expected push to throw when the bookkeeping model is not registered")
        } catch {
            // Expected: push throws rather than completing a stranded upload.
        }
        XCTAssertFalse(
            uploadCalled, "push must fail before uploading, so an acknowledged server write is never stranded")
    }

    private func mutate(_ context: ModelContext, _ body: ([PushNote]) -> Void) throws {
        body(try context.fetch(FetchDescriptor<PushNote>()))
        try context.save()
    }

    private func delete(_ id: String, in context: ModelContext) throws {
        if let row = try context.fetch(FetchDescriptor<PushNote>(predicate: #Predicate { $0.id == id })).first {
            context.delete(row)
        }
        try context.save()
    }
}
