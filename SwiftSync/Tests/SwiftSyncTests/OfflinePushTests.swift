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

    private func confirmAll(_ batch: SyncPushBatch) -> SyncPushResponse {
        SyncPushResponse(confirmedLocalIDs: Set(batch.inserts + batch.updates + batch.deletes))
    }

    /// History-derived partitioning: after a baseline push makes some rows "synced" (behind the
    /// cursor), a fresh round of local edits partitions into insert/update/delete — and a row inserted
    /// *and* deleted before any push is dropped, since the server never saw it.
    func testPartitionsPendingChangesFromHistory() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        for id in ["a", "b", "d"] { context.insert(PushNote(id: id, title: id)) }
        try context.save()
        // Baseline push: a, b, d become synced (cursor advances past their inserts).
        _ = try await SwiftSync.push(for: PushNote.self, in: context, upload: confirmAll)

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

    /// A fully-acknowledged push advances the cursor, so nothing is left pending afterwards.
    func testFullyAcknowledgedPushClearsPending() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "c1", title: "insert"))
        try context.save()

        let summary = try await SwiftSync.push(for: PushNote.self, in: context) { batch in
            XCTAssertEqual(batch.inserts, ["c1"])
            return self.confirmAll(batch)
        }

        XCTAssertEqual(summary.insertedCount, 1)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertTrue(try SwiftSync.pendingChanges(for: PushNote.self, in: context).isEmpty)
    }

    /// Pure-bubble: a rejected row's error is returned verbatim and nothing is written to the store, so
    /// the row stays pending (the cursor does not advance) and is re-detected next push.
    func testRejectedInsertBubblesAndStaysPending() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "c1", title: "rejected"))
        try context.save()

        let summary = try await SwiftSync.push(for: PushNote.self, in: context) { _ in
            SyncPushResponse(failures: [
                SyncPushFailure(localID: "c1", operation: .insert, error: PushTestError(message: "422"))
            ])
        }

        XCTAssertEqual(summary.failures.first?.localID, "c1")
        XCTAssertEqual(summary.failures.first?.error as? PushTestError, PushTestError(message: "422"))
        XCTAssertEqual(try SwiftSync.pendingChanges(for: PushNote.self, in: context).inserts, ["c1"])
    }

    /// An unacknowledged change must not advance the cursor, or it would silently fall out of detection.
    func testUnacknowledgedPushKeepsChangePending() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "u1", title: "v1"))
        try context.save()
        _ = try await SwiftSync.push(for: PushNote.self, in: context, upload: confirmAll)  // synced

        try mutate(context) { $0.first { $0.id == "u1" }?.title = "v2" }
        try context.save()

        _ = try await SwiftSync.push(for: PushNote.self, in: context) { _ in
            SyncPushResponse(failures: [
                SyncPushFailure(localID: "u1", operation: .update, error: PushTestError(message: "500"))
            ])
        }
        XCTAssertEqual(
            try SwiftSync.pendingChanges(for: PushNote.self, in: context).updates, ["u1"],
            "an unacknowledged update stays pending")
    }

    /// `updatedCount` reflects only rows actually in this batch, not extra ids the server echoes.
    func testUpdatedCountIgnoresIDsOutsideTheBatch() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PushNote(id: "u1", title: "v1"))
        try context.save()
        _ = try await SwiftSync.push(for: PushNote.self, in: context, upload: confirmAll)  // synced
        try mutate(context) { $0.first { $0.id == "u1" }?.title = "v2" }
        try context.save()

        let summary = try await SwiftSync.push(for: PushNote.self, in: context) { _ in
            SyncPushResponse(confirmedLocalIDs: ["u1", "ghost-not-in-batch"])
        }
        XCTAssertEqual(summary.updatedCount, 1, "only the in-batch update counts, not server echoes")
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
