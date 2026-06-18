import SwiftData
import XCTest

@testable import SwiftSync

@Model
final class OfflineNote: SyncOfflineModel {
    var syncLocalID: String
    var syncRemoteID: String?
    var syncUpdatedAt: Date
    var syncIsDeleted: Bool
    var syncFailureReason: String?
    var title: String

    init(
        syncLocalID: String, syncRemoteID: String?, syncUpdatedAt: Date, syncIsDeleted: Bool,
        title: String
    ) {
        self.syncLocalID = syncLocalID
        self.syncRemoteID = syncRemoteID
        self.syncUpdatedAt = syncUpdatedAt
        self.syncIsDeleted = syncIsDeleted
        self.title = title
    }
}

final class SyncPushTests: XCTestCase {
    @MainActor
    func testPartitionsPendingChanges() throws {
        let context = ModelContext(
            try ModelContainer(
                for: OfflineNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        let lastSync = Date(timeIntervalSince1970: 1_000)
        let beforeSync = Date(timeIntervalSince1970: 500)
        let afterSync = Date(timeIntervalSince1970: 1_500)

        // synced + untouched since last sync → not pushed
        context.insert(
            OfflineNote(
                syncLocalID: "a", syncRemoteID: "r-a", syncUpdatedAt: beforeSync, syncIsDeleted: false,
                title: "unchanged"))
        // synced + edited after last sync → update
        context.insert(
            OfflineNote(
                syncLocalID: "b", syncRemoteID: "r-b", syncUpdatedAt: afterSync, syncIsDeleted: false,
                title: "updated"))
        // never synced → insert
        context.insert(
            OfflineNote(
                syncLocalID: "c", syncRemoteID: nil, syncUpdatedAt: afterSync, syncIsDeleted: false,
                title: "inserted"))
        // synced + locally deleted → delete
        context.insert(
            OfflineNote(
                syncLocalID: "d", syncRemoteID: "r-d", syncUpdatedAt: afterSync, syncIsDeleted: true,
                title: "deleted"))
        // inserted then deleted locally (never reached server) → dropped, not pushed
        context.insert(
            OfflineNote(
                syncLocalID: "e", syncRemoteID: nil, syncUpdatedAt: afterSync, syncIsDeleted: true,
                title: "inserted-then-deleted"))
        try context.save()

        let pending = try SwiftSync.pendingChanges(
            for: OfflineNote.self, in: context, changedSince: lastSync)

        XCTAssertEqual(pending.inserts.map(\.syncLocalID).sorted(), ["c"])
        XCTAssertEqual(pending.updates.map(\.syncLocalID).sorted(), ["b"])
        XCTAssertEqual(pending.deletes.map(\.syncLocalID).sorted(), ["d"])
    }

    @MainActor
    func testPushAppliesServerResponse() async throws {
        let context = ModelContext(
            try ModelContainer(
                for: OfflineNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let lastSync = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        let edited = Date(timeIntervalSince1970: 1_500)

        context.insert(
            OfflineNote(
                syncLocalID: "c1", syncRemoteID: nil, syncUpdatedAt: edited, syncIsDeleted: false,
                title: "insert"))
        context.insert(
            OfflineNote(
                syncLocalID: "u1", syncRemoteID: "r-u1", syncUpdatedAt: edited, syncIsDeleted: false,
                title: "update"))
        context.insert(
            OfflineNote(
                syncLocalID: "d1", syncRemoteID: "r-d1", syncUpdatedAt: edited, syncIsDeleted: true,
                title: "delete"))
        try context.save()

        let summary = try await SwiftSync.push(
            for: OfflineNote.self, in: context, changedSince: lastSync, now: now
        ) { batch in
            // Stand-in for the app's network call: server accepts everything.
            XCTAssertEqual(batch.inserts, ["c1"])
            return SyncPushResponse(
                assignedRemoteIDs: ["c1": "server-c1"],
                confirmedUpdateLocalIDs: ["u1"],
                confirmedDeleteLocalIDs: ["d1"])
        }

        let rows = try context.fetch(FetchDescriptor<OfflineNote>())
        let byLocalID = Dictionary(uniqueKeysWithValues: rows.map { ($0.syncLocalID, $0) })

        XCTAssertEqual(byLocalID["c1"]?.syncRemoteID, "server-c1", "insert must get its server id")
        XCTAssertNil(byLocalID["d1"], "confirmed delete must be hard-deleted")
        XCTAssertEqual(summary.insertedCount, 1)
        XCTAssertEqual(summary.updatedCount, 1)
        XCTAssertEqual(summary.deletedCount, 1)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(summary.cursor, now)
    }

    @MainActor
    func testPushSurfacesFailures() async throws {
        let context = ModelContext(
            try ModelContainer(
                for: OfflineNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        context.insert(
            OfflineNote(
                syncLocalID: "c1", syncRemoteID: nil, syncUpdatedAt: Date(timeIntervalSince1970: 1_500),
                syncIsDeleted: false, title: "rejected insert"))
        try context.save()

        let summary = try await SwiftSync.push(
            for: OfflineNote.self, in: context, changedSince: Date(timeIntervalSince1970: 1_000)
        ) { _ in
            SyncPushResponse(failures: [
                SyncPushFailure(localID: "c1", operation: .insert, message: "422 invalid")
            ])
        }

        XCTAssertEqual(
            summary.failures,
            [
                SyncPushFailure(localID: "c1", operation: .insert, message: "422 invalid")
            ])
        let rows = try context.fetch(FetchDescriptor<OfflineNote>())
        XCTAssertNil(rows.first?.syncRemoteID, "a rejected insert keeps no remote id and stays local")
    }

    /// P1: a failed (or unacknowledged) update is cursor-gated, so the cursor must NOT advance past
    /// it — otherwise it silently disappears from future detection and the edit is lost.
    @MainActor
    func testPushDoesNotAdvanceCursorWhenAnUpdateIsUnacknowledged() async throws {
        let context = ModelContext(
            try ModelContainer(
                for: OfflineNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let lastSync = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        context.insert(
            OfflineNote(
                syncLocalID: "u1", syncRemoteID: "r-u1", syncUpdatedAt: Date(timeIntervalSince1970: 1_500),
                syncIsDeleted: false, title: "update that fails"))
        try context.save()

        let summary = try await SwiftSync.push(
            for: OfflineNote.self, in: context, changedSince: lastSync, now: now
        ) { _ in
            SyncPushResponse(failures: [
                SyncPushFailure(localID: "u1", operation: .update, message: "500")
            ])
        }

        XCTAssertEqual(summary.cursor, lastSync, "cursor must not advance past an unacknowledged update")
        // Following the contract (advance to summary.cursor) must still re-detect the failed update.
        let stillPending = try SwiftSync.pendingChanges(
            for: OfflineNote.self, in: context, changedSince: summary.cursor)
        XCTAssertEqual(stillPending.updates.map(\.syncLocalID), ["u1"])
    }

    /// A persisted failure must clear only on *actual* success, never merely because the server's
    /// response didn't mention the row. An unacknowledged row is still pending (the cursor logic agrees
    /// — it doesn't advance past it), so silently dropping its failure marker would make it vanish from
    /// the failures inbox while still unsynced.
    @MainActor
    func testPushKeepsFailureReasonForUnacknowledgedRows() async throws {
        let context = ModelContext(
            try ModelContainer(
                for: OfflineNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let lastSync = Date(timeIntervalSince1970: 1_000)
        let edited = Date(timeIntervalSince1970: 1_500)

        // An insert and an update, both already flagged from a prior push.
        let insert = OfflineNote(
            syncLocalID: "c1", syncRemoteID: nil, syncUpdatedAt: edited, syncIsDeleted: false,
            title: "failed insert")
        insert.syncFailureReason = "422 invalid"
        context.insert(insert)
        let update = OfflineNote(
            syncLocalID: "u1", syncRemoteID: "r-u1", syncUpdatedAt: edited, syncIsDeleted: false,
            title: "failed update")
        update.syncFailureReason = "500 server error"
        context.insert(update)
        try context.save()

        // The next push returns nothing for either row — neither acknowledged nor freshly failed.
        _ = try await SwiftSync.push(
            for: OfflineNote.self, in: context, changedSince: lastSync,
            now: Date(timeIntervalSince1970: 2_000)
        ) { _ in SyncPushResponse() }

        let rows = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<OfflineNote>()).map { ($0.syncLocalID, $0) })
        XCTAssertEqual(
            rows["c1"]?.syncFailureReason, "422 invalid", "an unacknowledged insert keeps its failure")
        XCTAssertEqual(
            rows["u1"]?.syncFailureReason, "500 server error", "an unacknowledged update keeps its failure")
    }

    /// `updatedCount` must reflect only rows that were actually in this push batch, not whatever
    /// ids the server echoed back.
    @MainActor
    func testPushUpdatedCountIgnoresIDsOutsideTheBatch() async throws {
        let context = ModelContext(
            try ModelContainer(
                for: OfflineNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        context.insert(
            OfflineNote(
                syncLocalID: "u1", syncRemoteID: "r-u1", syncUpdatedAt: Date(timeIntervalSince1970: 1_500),
                syncIsDeleted: false, title: "update"))
        try context.save()

        let summary = try await SwiftSync.push(
            for: OfflineNote.self, in: context, changedSince: Date(timeIntervalSince1970: 1_000),
            now: Date(timeIntervalSince1970: 2_000)
        ) { _ in
            SyncPushResponse(confirmedUpdateLocalIDs: ["u1", "ghost-not-in-batch"])
        }

        XCTAssertEqual(summary.updatedCount, 1, "only the in-batch update counts, not server echoes")
    }
}
