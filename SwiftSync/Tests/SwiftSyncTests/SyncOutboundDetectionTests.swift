import SwiftData
import XCTest

@testable import SwiftSync

@Model
final class OfflineNote: SyncOfflineModel {
    var syncLocalID: String
    var syncRemoteID: String?
    var syncUpdatedAt: Date
    var syncIsDeleted: Bool
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

final class SyncOutboundDetectionTests: XCTestCase {
    @MainActor
    func testPartitionsPendingOutboundChanges() throws {
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
        // never synced → create
        context.insert(
            OfflineNote(
                syncLocalID: "c", syncRemoteID: nil, syncUpdatedAt: afterSync, syncIsDeleted: false,
                title: "created"))
        // synced + locally deleted → delete
        context.insert(
            OfflineNote(
                syncLocalID: "d", syncRemoteID: "r-d", syncUpdatedAt: afterSync, syncIsDeleted: true,
                title: "deleted"))
        // created then deleted locally (never reached server) → dropped, not pushed
        context.insert(
            OfflineNote(
                syncLocalID: "e", syncRemoteID: nil, syncUpdatedAt: afterSync, syncIsDeleted: true,
                title: "created-then-deleted"))
        try context.save()

        let pending = try SwiftSync.pendingOutboundChanges(
            for: OfflineNote.self, in: context, changedSince: lastSync)

        XCTAssertEqual(pending.creates.map(\.syncLocalID).sorted(), ["c"])
        XCTAssertEqual(pending.updates.map(\.syncLocalID).sorted(), ["b"])
        XCTAssertEqual(pending.deletes.map(\.syncLocalID).sorted(), ["d"])
    }
}
