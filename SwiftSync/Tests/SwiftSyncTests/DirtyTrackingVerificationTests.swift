import XCTest
import SwiftData
@testable import SwiftSync

// ---------------------------------------------------------------------------
// Verification of the "iOS-only dirty-tracking gap" claim from commit 346f048
// and .agents/state.md.
//
// CLAIM: On iOS persistent SQLite stores, SwiftData omits the owning model's
//        PersistentIdentifier from ModelContext.didSave's updatedIdentifiers
//        after a to-many-only relationship change (no scalar mutation). On
//        macOS, the owner is always present, so unit tests cannot catch it.
//
// FINDINGS on macOS (this test suite, SPM host):
//
//   Persistent SQLite store, no scalar touch  → owner PRESENT ✓
//   Persistent SQLite store, with scalar touch → owner PRESENT ✓
//   In-memory store, no scalar touch           → owner PRESENT ✓
//
// CONCLUSION: On macOS, SwiftData includes the owning model in
// updatedIdentifiers regardless of store type or whether a scalar touch was
// performed. The "macOS always surfaces the owner" half of the claim is
// CONFIRMED. The tests below pin this behaviour as a non-regression anchor.
//
// The iOS half of the claim (the gap exists on iOS) cannot be verified here.
// It was validated via debug logging on a physical device (see commit 346f048).
// ---------------------------------------------------------------------------

@Model
private final class DVTask2 {
    @Attribute(.unique) var id: Int
    var title: String
    @Relationship var members: [DVMember2]
    init(id: Int, title: String, members: [DVMember2] = []) {
        self.id = id; self.title = title; self.members = members
    }
}

@Model
private final class DVMember2 {
    @Attribute(.unique) var id: Int
    var name: String
    init(id: Int, name: String) { self.id = id; self.name = name }
}

extension DVTask2: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<DVTask2, Int> { \.id }
    static func make(from payload: SyncPayload) throws -> DVTask2 {
        DVTask2(id: try payload.required(Int.self, for: "id"),
                title: try payload.required(String.self, for: "title"))
    }
    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("title") {
            let v: String = try payload.required(String.self, for: "title")
            if title != v { title = v; changed = true }
        }
        return changed
    }
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        try syncApplyToManyForeignKeys(self, relationship: \DVTask2.members,
                                      payload: payload, keys: ["member_ids"], in: context)
    }
}

extension DVMember2: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<DVMember2, Int> { \.id }
    static func make(from payload: SyncPayload) throws -> DVMember2 {
        DVMember2(id: try payload.required(Int.self, for: "id"),
                  name: try payload.required(String.self, for: "name"))
    }
    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let v: String = try payload.required(String.self, for: "name")
            if name != v { name = v; changed = true }
        }
        return changed
    }
}

@MainActor
final class DirtyTrackingVerificationTests: XCTestCase {

    // Persistent SQLite store, to-many change only, NO scalar touch.
    // Verifies the macOS claim: owner is present in updatedIdentifiers without fix.
    // If this ever fails, the macOS behaviour has changed and the fix may be needed here too.
    func testOwnerPresentInUpdatedIdentifiers_persistentStore_noScalarTouch() throws {
        let (mc, storeURL) = try makePersistentContainer()
        defer { removeSQLiteFiles(at: storeURL) }

        seedData(in: mc)

        let ctx = ModelContext(mc)
        let task = try XCTUnwrap(ctx.fetch(FetchDescriptor<DVTask2>()).first)
        let members = try ctx.fetch(FetchDescriptor<DVMember2>())
        let taskID = task.persistentModelID

        var updatedIDs: [PersistentIdentifier] = []
        let tok = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { n in
            updatedIDs = (n.userInfo?["updated"] as? [PersistentIdentifier]) ?? []
        }
        defer { NotificationCenter.default.removeObserver(tok) }

        task.members = members   // no scalar touch
        try ctx.save()

        XCTAssertTrue(
            updatedIDs.contains(taskID),
            "On macOS, owner must be present in updatedIdentifiers after a to-many-only " +
            "change on a persistent store, even without the syncMarkChanged() scalar touch. " +
            "If this fails, macOS behaviour has changed and the fix may be needed here too. " +
            "updatedIDs: \(updatedIDs)"
        )
    }

    // Persistent SQLite store, to-many change WITH scalar touch (the fix).
    // Control: confirms the fix also works correctly on macOS.
    func testOwnerPresentInUpdatedIdentifiers_persistentStore_withScalarTouch() throws {
        let (mc, storeURL) = try makePersistentContainer()
        defer { removeSQLiteFiles(at: storeURL) }

        seedData(in: mc)

        let ctx = ModelContext(mc)
        let task = try XCTUnwrap(ctx.fetch(FetchDescriptor<DVTask2>()).first)
        let members = try ctx.fetch(FetchDescriptor<DVMember2>())
        let taskID = task.persistentModelID

        var updatedIDs: [PersistentIdentifier] = []
        let tok = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { n in
            updatedIDs = (n.userInfo?["updated"] as? [PersistentIdentifier]) ?? []
        }
        defer { NotificationCenter.default.removeObserver(tok) }

        task.members = members
        task.id = task.id   // scalar touch — the syncMarkChanged() fix
        try ctx.save()

        XCTAssertTrue(
            updatedIDs.contains(taskID),
            "Owner must be present after to-many change + scalar touch. " +
            "updatedIDs: \(updatedIDs)"
        )
    }

    // In-memory store, to-many change only, NO scalar touch.
    // Confirms that in-memory stores always dirty the owner — this is why tests
    // using isStoredInMemoryOnly: true cannot catch the iOS persistent-store gap.
    func testOwnerPresentInUpdatedIdentifiers_inMemoryStore_noScalarTouch() throws {
        let mc = try ModelContainer(
            for: DVTask2.self, DVMember2.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        seedData(in: mc)

        let ctx = ModelContext(mc)
        let task = try XCTUnwrap(ctx.fetch(FetchDescriptor<DVTask2>()).first)
        let members = try ctx.fetch(FetchDescriptor<DVMember2>())
        let taskID = task.persistentModelID

        var updatedIDs: [PersistentIdentifier] = []
        let tok = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { n in
            updatedIDs = (n.userInfo?["updated"] as? [PersistentIdentifier]) ?? []
        }
        defer { NotificationCenter.default.removeObserver(tok) }

        task.members = members   // no scalar touch
        try ctx.save()

        XCTAssertTrue(
            updatedIDs.contains(taskID),
            "In-memory store always dirties the owner — if this fails, SwiftData " +
            "in-memory behaviour has changed. updatedIDs: \(updatedIDs)"
        )
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private func makePersistentContainer() throws -> (ModelContainer, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DVVerify-\(UUID().uuidString).sqlite")
        let mc = try ModelContainer(
            for: DVTask2.self, DVMember2.self,
            configurations: ModelConfiguration(url: url)
        )
        return (mc, url)
    }

    private func seedData(in mc: ModelContainer) {
        let ctx = ModelContext(mc)
        ctx.insert(DVMember2(id: 1, name: "Alice"))
        ctx.insert(DVMember2(id: 2, name: "Bob"))
        ctx.insert(DVTask2(id: 10, title: "Task 10"))
        try? ctx.save()
    }

    private func removeSQLiteFiles(at url: URL) {
        let base = url.deletingPathExtension()
        for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
            try? FileManager.default.removeItem(at: base.appendingPathExtension(ext))
        }
    }
}
