import SwiftData
import XCTest

@testable import SwiftSync

@Model
final class OpsCompany {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

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

extension OpsEmployee {
    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
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
            // Strict FK typing: a mismatched key type is ignored, not coerced.
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

final class RelationshipOperationsTests: XCTestCase {

    @MainActor
    func testRelationshipOperationsSkipRelationshipUpdatesWhenUpdateFlagMissing() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: OpsCompany.self, OpsEmployee.self, configurations: configuration)
        let context = ModelContext(container)

        try await context.sync(payload: [["id": 10, "name": "Acme"]], as: OpsCompany.self)

        try await context.sync(
            payload: [["id": 1, "name": "Ava", "company_id": 10]], as: OpsEmployee.self,
            relationshipOperations: [.insert])

        var rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)

        try await context.sync(
            payload: [["id": 1, "name": "Ava", "company_id": NSNull()]], as: OpsEmployee.self,
            relationshipOperations: [.insert])

        rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)

        try await context.sync(
            payload: [["id": 1, "name": "Ava", "company_id": NSNull()]], as: OpsEmployee.self,
            relationshipOperations: [.update])

        rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertNil(rows.first?.company)
    }
}
