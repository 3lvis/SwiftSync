import SwiftData
import XCTest

@testable import SwiftSync

// Models that bolt modern SwiftData features onto an otherwise-correct @Syncable model,
// to characterise how those features interact with SwiftSync's identity/upsert patterns.

@Syncable
@Model
final class InteropIndexedNote {
    #Index<InteropIndexedNote>([\.category])
    @Attribute(.unique) var id: Int
    var title: String
    var category: String
    init(id: Int, title: String, category: String) {
        self.id = id
        self.title = title
        self.category = category
    }
}

@Syncable
@Model
final class InteropUniqueEmailUser {
    @Attribute(.unique) var id: Int
    @Attribute(.unique) var email: String
    var name: String
    init(id: Int, email: String, name: String) {
        self.id = id
        self.email = email
        self.name = name
    }
}

@Syncable
@Model
final class InteropCompoundUniqueEvent {
    #Unique<InteropCompoundUniqueEvent>([\.name, \.day])
    @Attribute(.unique) var id: Int
    var name: String
    var day: String
    init(id: Int, name: String, day: String) {
        self.id = id
        self.name = name
        self.day = day
    }
}

final class SyncFeatureInteropTests: XCTestCase {

    /// `#Index` only affects query planning, so identity-based upsert is unaffected — safe to use freely.
    @MainActor
    func testIndexOnNonIdentityFieldIsTransparentToSync() async throws {
        let context = ModelContext(
            try ModelContainer(
                for: InteropIndexedNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        try await context.sync(
            payload: [
                ["id": 1, "title": "A", "category": "x"],
                ["id": 2, "title": "B", "category": "x"],
            ], as: InteropIndexedNote.self)

        try await context.sync(item: ["id": 1, "title": "A2", "category": "y"], as: InteropIndexedNote.self)

        let notes = try context.fetch(FetchDescriptor<InteropIndexedNote>())
        XCTAssertEqual(notes.count, 2, "#Index must not change row identity or count")
        XCTAssertEqual(
            notes.first { $0.id == 1 }?.title, "A2", "upsert-by-id must still update in place")
    }

    @MainActor
    func testUniqueOnNonIdentityFieldCausesSilentSyncDataLoss() async throws {
        XCTExpectFailure(
            "Known incompatibility: a unique constraint on a non-identity property lets SwiftData's constraint-based upsert destroy identity-distinct rows during sync. Declare uniqueness only on the sync identity."
        )

        let context = ModelContext(
            try ModelContainer(
                for: InteropUniqueEmailUser.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        try await context.sync(item: ["id": 1, "email": "a@x.com", "name": "Alice"], as: InteropUniqueEmailUser.self)
        // Distinct sync identity (id 2), but collides on the unique email.
        try await context.sync(item: ["id": 2, "email": "a@x.com", "name": "Bob"], as: InteropUniqueEmailUser.self)

        let users = try context.fetch(FetchDescriptor<InteropUniqueEmailUser>())
        XCTAssertEqual(users.count, 2, "both identity-distinct rows should survive")
        XCTAssertTrue(users.contains { $0.id == 1 }, "the original row must not be destroyed")
    }

    @MainActor
    func testCompoundUniqueOnSyncedFieldsCausesSilentSyncDataLoss() async throws {
        XCTExpectFailure(
            "Known incompatibility: compound #Unique on synced fields lets SwiftData destroy identity-distinct rows during sync. Declare uniqueness only on the sync identity."
        )

        let context = ModelContext(
            try ModelContainer(
                for: InteropCompoundUniqueEvent.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        try await context.sync(item: ["id": 1, "name": "Launch", "day": "Mon"], as: InteropCompoundUniqueEvent.self)
        try await context.sync(item: ["id": 2, "name": "Launch", "day": "Mon"], as: InteropCompoundUniqueEvent.self)

        let events = try context.fetch(FetchDescriptor<InteropCompoundUniqueEvent>())
        XCTAssertEqual(events.count, 2, "both identity-distinct rows should survive")
        XCTAssertTrue(events.contains { $0.id == 1 }, "the original row must not be destroyed")
    }

    @MainActor
    func testSyncContainerAcceptsIndexAndIdentityUniqueModel() throws {
        XCTAssertNoThrow(
            try SyncContainer(
                for: InteropIndexedNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @MainActor
    func testSyncContainerRejectsUniqueOnNonIdentityField() throws {
        XCTAssertThrowsError(
            try SyncContainer(
                for: InteropUniqueEmailUser.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        ) { error in
            XCTAssertTrue(
                {
                    if case SyncError.schemaValidation = error { return true }
                    return false
                }(),
                "expected SchemaValidationError, got \(error)")
        }
    }

    @MainActor
    func testSyncContainerRejectsCompoundUniqueOnNonIdentityFields() throws {
        XCTAssertThrowsError(
            try SyncContainer(
                for: InteropCompoundUniqueEvent.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        ) { error in
            XCTAssertTrue(
                {
                    if case SyncError.schemaValidation = error { return true }
                    return false
                }(),
                "expected SchemaValidationError, got \(error)")
        }
    }
}
