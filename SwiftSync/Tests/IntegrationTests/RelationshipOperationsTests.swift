// RelationshipOperationsTests.swift
//
// Tests for SyncRelationshipOperations — the bitmask that controls which
// relationship mutations the sync engine is allowed to perform on a given
// sync call.
//
// ## Background
//
// `SyncRelationshipOperations` is an OptionSet with three flags:
//   - `.insert`  — set relationships when a row is newly created
//   - `.update`  — re-link or mutate relationships on an existing row
//   - `.delete`  — clear relationships (set to nil / remove members)
//   - `.all`     — convenience combining all three (the default)
//
// The sync engine checks these flags at two layers:
//
// 1. **API.swift entry point** — decides whether to call
//    `applyRelationships` at all based on new-row vs existing-row:
//    - Existing row: only calls `applyRelationships` if the mask
//      contains `.update` or `.delete`.
//    - Newly inserted row: only calls `applyRelationships` if the
//      mask contains `.insert`.
//
// 2. **Free helper functions** (`syncApplyToOneForeignKey`, etc.) —
//    perform fine-grained checks per flag to decide whether to link,
//    clear, create, or mutate related objects.
//
// ## Why this exists
//
// Phased sync workflows sometimes need to insert rows without wiring
// up their relationships (e.g., when related objects haven't been synced
// yet and FK lookups would fail). Passing `relationshipOperations: [.insert]`
// allows the first pass to create rows and set relationships only on
// newly inserted rows, while a later pass with `.update` re-wires
// existing rows.
//
// ## Historical note
//
// These tests originally lived in IntegrationTests.swift alongside the
// `OpsCompany` and `OpsEmployee` models. The models are hand-written
// (not @Syncable) to exercise the `operations:` parameter threading
// manually. They formerly conformed to the now-removed
// `SyncRelationshipUpdatableModel` protocol, which has been collapsed
// into `SyncUpdatableModel`.

import XCTest
import SwiftData
import SwiftSync

// MARK: - Test Models

/// A minimal company model with no relationships, used as the FK target
/// for `OpsEmployee`. Hand-written (not @Syncable) to keep the operations
/// test surface explicit.
@Model
final class OpsCompany {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// An employee model with an optional to-one FK to `OpsCompany`.
/// Hand-written (not @Syncable) so the `applyRelationships` implementation
/// can explicitly thread the `operations:` parameter and use `strictValue`
/// for type-safe FK resolution.
@Model
final class OpsEmployee {
    @Attribute(.unique) var id: Int
    var name: String
    var company: OpsCompany?

    init(id: Int, name: String, company: OpsCompany? = nil) {
        self.id = id
        self.name = name
        self.company = company
    }
}

// MARK: - SyncUpdatableModel Conformances

extension OpsCompany: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<OpsCompany, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OpsCompany {
        OpsCompany(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incoming: String = try payload.required(String.self, for: "name")
            if name != incoming {
                name = incoming
                changed = true
            }
        }
        return changed
    }
}

extension OpsEmployee: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<OpsEmployee, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OpsEmployee {
        OpsEmployee(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incoming: String = try payload.required(String.self, for: "name")
            if name != incoming {
                name = incoming
                changed = true
            }
        }
        return changed
    }
}

/// Hand-written `applyRelationships` that explicitly checks the operations
/// mask before performing any FK mutation. This mirrors what the @Syncable
/// macro generates via `syncApplyToOneForeignKey`, but done manually so
/// the test can validate the engine's operation-gating behavior at the
/// API.swift layer (which decides whether to call `applyRelationships`
/// at all based on the mask and whether the row is new or existing).
extension OpsEmployee {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool {
        guard !operations.isDisjoint(with: [.insert, .update, .delete]) else { return false }
        guard payload.contains("company_id") else { return false }

        if payload.value(for: "company_id", as: NSNull.self) != nil {
            if company != nil {
                company = nil
                return true
            }
            return false
        }

        guard let companyID: Int = payload.strictValue(for: "company_id") else {
            // Strict foreign-key typing: mismatched key type is ignored.
            return false
        }

        let companies = try context.fetch(FetchDescriptor<OpsCompany>())
        let nextCompany = companies.first(where: { $0.id == companyID })
        guard let nextCompany else {
            return false
        }

        if company?.id != nextCompany.id {
            company = nextCompany
            return true
        }
        return false
    }
}

// MARK: - Tests

final class RelationshipOperationsTests: XCTestCase {

    /// Validates that the `relationshipOperations` bitmask correctly gates
    /// relationship mutations based on whether a row is newly inserted vs
    /// already existing.
    ///
    /// Scenario (phased sync):
    /// 1. Sync a company (id=10).
    /// 2. Sync an employee with `relationshipOperations: [.insert]` and
    ///    `company_id: 10`. Because the employee is newly inserted and
    ///    `.insert` is in the mask, the FK **is** resolved.
    /// 3. Re-sync the same employee with `relationshipOperations: [.insert]`
    ///    and `company_id: NSNull()`. The employee already exists, so the
    ///    engine checks `isDisjoint(with: [.update, .delete])` — since
    ///    `[.insert]` IS disjoint, `applyRelationships` is never called.
    ///    The FK **stays** linked.
    /// 4. Re-sync with `relationshipOperations: [.update]` and
    ///    `company_id: NSNull()`. Now `.update` passes the disjoint check,
    ///    `applyRelationships` fires, and the FK **is** cleared.
    @MainActor
    func testRelationshipOperationsSkipRelationshipUpdatesWhenUpdateFlagMissing() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: OpsCompany.self, OpsEmployee.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "Acme"]],
            as: OpsCompany.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": 10]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.insert]
        )

        var rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": NSNull()]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.insert]
        )

        rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": NSNull()]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.update]
        )

        rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertNil(rows.first?.company)
    }
}
