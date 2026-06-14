import SwiftData
import XCTest

@testable import SwiftSync

// Models that bolt modern SwiftData features onto an otherwise-correct @Syncable model,
// to characterise how those features interact with SwiftSync's identity/upsert patterns.

// `#Index` on a non-identity field.
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

// `@Attribute(.unique)` on a non-identity field.
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

// Compound `#Unique` across non-identity fields.
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

    /// `#Index` on a non-identity property is transparent to SwiftSync: it only affects query
    /// planning, so identity-based upsert is unaffected. This is the "safe to use freely" case.
    @MainActor
    func testIndexOnNonIdentityFieldIsTransparentToSync() async throws {
        let context = ModelContext(
            try ModelContainer(
                for: InteropIndexedNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "title": "A", "category": "x"],
                ["id": 2, "title": "B", "category": "x"],
            ], as: InteropIndexedNote.self, in: context)

        // Re-sync id 1 with changed fields — must update the same row, not create a new one.
        try await SwiftSync.sync(
            item: ["id": 1, "title": "A2", "category": "y"], as: InteropIndexedNote.self,
            in: context)

        let notes = try context.fetch(FetchDescriptor<InteropIndexedNote>())
        XCTAssertEqual(notes.count, 2, "#Index must not change row identity or count")
        XCTAssertEqual(
            notes.first { $0.id == 1 }?.title, "A2", "upsert-by-id must still update in place")
    }

    /// A unique constraint on a *non-identity* property breaks SwiftSync's core invariant
    /// (one row per `syncIdentity`). When sync inserts an identity-distinct row whose unique
    /// field collides with an existing row, SwiftData performs a constraint-based upsert and
    /// silently overwrites/destroys the other row — local data ends up disagreeing with the
    /// backend, with no error. Put uniqueness only on the sync identity.
    @MainActor
    func testUniqueOnNonIdentityFieldCausesSilentSyncDataLoss() async throws {
        XCTExpectFailure(
            "Known incompatibility: a unique constraint on a non-identity property lets SwiftData's constraint-based upsert destroy identity-distinct rows during sync. Declare uniqueness only on the sync identity."
        )

        let context = ModelContext(
            try ModelContainer(
                for: InteropUniqueEmailUser.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        try await SwiftSync.sync(
            item: ["id": 1, "email": "a@x.com", "name": "Alice"], as: InteropUniqueEmailUser.self,
            in: context)
        // id 2 is a distinct record per SwiftSync identity, but collides on the unique email.
        try await SwiftSync.sync(
            item: ["id": 2, "email": "a@x.com", "name": "Bob"], as: InteropUniqueEmailUser.self,
            in: context)

        let users = try context.fetch(FetchDescriptor<InteropUniqueEmailUser>())
        XCTAssertEqual(users.count, 2, "both identity-distinct rows should survive")
        XCTAssertTrue(users.contains { $0.id == 1 }, "the original row must not be destroyed")
    }

    /// Compound `#Unique` across non-identity fields has the same hazard as a single-field
    /// unique constraint: an identity-distinct row that collides on the compound key destroys
    /// the existing row during sync.
    @MainActor
    func testCompoundUniqueOnSyncedFieldsCausesSilentSyncDataLoss() async throws {
        XCTExpectFailure(
            "Known incompatibility: compound #Unique on synced fields lets SwiftData destroy identity-distinct rows during sync. Declare uniqueness only on the sync identity."
        )

        let context = ModelContext(
            try ModelContainer(
                for: InteropCompoundUniqueEvent.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))

        try await SwiftSync.sync(
            item: ["id": 1, "name": "Launch", "day": "Mon"], as: InteropCompoundUniqueEvent.self,
            in: context)
        try await SwiftSync.sync(
            item: ["id": 2, "name": "Launch", "day": "Mon"], as: InteropCompoundUniqueEvent.self,
            in: context)

        let events = try context.fetch(FetchDescriptor<InteropCompoundUniqueEvent>())
        XCTAssertEqual(events.count, 2, "both identity-distinct rows should survive")
        XCTAssertTrue(events.contains { $0.id == 1 }, "the original row must not be destroyed")
    }

    // MARK: - Guardrail: SyncContainer refuses the data-loss footgun at init

    /// `#Index` on a non-identity field is safe, so a `SyncContainer` built from such a model
    /// initialises normally.
    @MainActor
    func testSyncContainerAcceptsIndexAndIdentityUniqueModel() throws {
        XCTAssertNoThrow(
            try SyncContainer(
                for: InteropIndexedNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// A `@Syncable` model with `@Attribute(.unique)` on a non-identity field must be rejected at
    /// `SyncContainer` init — same guardrail style as the many-to-many inverse check.
    @MainActor
    func testSyncContainerRejectsUniqueOnNonIdentityField() throws {
        XCTAssertThrowsError(
            try SyncContainer(
                for: InteropUniqueEmailUser.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        ) { error in
            XCTAssertTrue(
                error is SyncContainer.SchemaValidationError,
                "expected SchemaValidationError, got \(error)")
        }
    }

    /// Compound `#Unique` across non-identity fields is rejected at `SyncContainer` init.
    @MainActor
    func testSyncContainerRejectsCompoundUniqueOnNonIdentityFields() throws {
        XCTAssertThrowsError(
            try SyncContainer(
                for: InteropCompoundUniqueEvent.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        ) { error in
            XCTAssertTrue(
                error is SyncContainer.SchemaValidationError,
                "expected SchemaValidationError, got \(error)")
        }
    }
}
