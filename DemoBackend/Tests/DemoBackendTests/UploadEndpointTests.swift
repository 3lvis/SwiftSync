import Foundation
import XCTest

@testable import DemoBackend

final class UploadEndpointTests: XCTestCase {
    private let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
    private let authorID = DemoSeedData.SeedIDs.Users.avaMartinez

    func testUploadUpsertAdoptsPublicIDAndIsIdempotent() throws {
        let backend = try makeBackend()
        let localID = "11111111-1111-1111-1111-111111111111"
        let before = try backend.getProjectTasksPayload(projectID: projectID).count

        let first = try result(of: backend.upload(operations: [upsertOp(localID: localID, title: "Offline task")]))
        XCTAssertEqual(first["status"] as? String, "applied")
        XCTAssertEqual(first["localId"] as? String, localID)
        // The internal int id never leaves the server — no remoteId in the response.
        XCTAssertNil(first["remoteId"])

        let tasks = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertEqual(tasks.count, before + 1)
        // The client's localId is adopted as the row's public_id (its sole identity).
        let inserted = try XCTUnwrap(tasks.first { ($0["id"] as? String) == localID })
        XCTAssertNil(inserted["local_id"])

        // Re-upsert the same public_id (lost-response retry): no duplicate row. The identical updatedAt
        // loses the LWW tie, so it's a converged no-op — not a failure.
        let retry = try result(of: backend.upload(operations: [upsertOp(localID: localID, title: "Offline task")]))
        XCTAssertNotEqual(retry["status"] as? String, "rejected")
        XCTAssertNil(retry["remoteId"])
        XCTAssertEqual(try backend.getProjectTasksPayload(projectID: projectID).count, before + 1)
    }

    func testUploadUpsertIsLastWriterWins() throws {
        let backend = try makeBackend()
        let localID = "22222222-2222-2222-2222-222222222222"
        let created = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Original", updatedAt: "2026-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(created["status"] as? String, "applied")

        // Older write loses: kept server state returned, title unchanged.
        let stale = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Stale edit", updatedAt: "2020-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(stale["status"] as? String, "stale")
        XCTAssertNil(stale["remoteId"])
        let server = try XCTUnwrap(stale["server"] as? [String: Any])
        XCTAssertEqual(server["title"] as? String, "Original")
        XCTAssertEqual(server["id"] as? String, localID)

        // Newer write wins.
        let applied = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Fresh edit", updatedAt: "2030-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(applied["status"] as? String, "applied")
        let detail = try XCTUnwrap(backend.getTaskDetailPayload(publicID: localID))
        XCTAssertEqual(detail["title"] as? String, "Fresh edit")
    }

    func testUploadDeleteTombstonesAndHidesFromReads() throws {
        let backend = try makeBackend()
        let localID = "33333333-3333-3333-3333-333333333333"
        _ = try result(of: backend.upload(operations: [upsertOp(localID: localID, title: "Doomed")]))

        let deleted = try result(
            of: backend.upload(operations: [
                deleteOp(localID: localID, updatedAt: "2030-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(deleted["status"] as? String, "applied")

        XCTAssertNil(try backend.getTaskDetailPayload(publicID: localID), "tombstoned row is hidden from detail")
        XCTAssertFalse(
            try backend.getProjectTasksPayload(projectID: projectID).contains {
                ($0["id"] as? String) == localID
            },
            "tombstoned row is hidden from the list")
    }

    func testUploadDeleteIsLastWriterWins() throws {
        let backend = try makeBackend()
        let localID = "44444444-4444-4444-4444-444444444444"
        _ = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Live", updatedAt: "2030-01-01T00:00:00.000Z")
            ]))

        // A delete older than the server's version must lose: stale + server state, not a tombstone.
        let stale = try result(
            of: backend.upload(operations: [
                deleteOp(localID: localID, updatedAt: "2020-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(stale["status"] as? String, "stale")
        XCTAssertNotNil(stale["server"] as? [String: Any])
        XCTAssertNotNil(
            try backend.getTaskDetailPayload(publicID: localID), "a stale delete must not tombstone the row")

        // A newer delete wins.
        let applied = try result(
            of: backend.upload(operations: [
                deleteOp(localID: localID, updatedAt: "2040-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(applied["status"] as? String, "applied")
        XCTAssertNil(try backend.getTaskDetailPayload(publicID: localID))
    }

    func testUploadUpsertRevivesTombstonedRowWhenEditIsNewer() throws {
        let backend = try makeBackend()
        let localID = "55555555-5555-5555-5555-555555555555"
        _ = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Live", updatedAt: "2030-01-01T00:00:00.000Z")
            ]))
        _ = try result(
            of: backend.upload(operations: [
                deleteOp(localID: localID, updatedAt: "2040-01-01T00:00:00.000Z")
            ]))
        XCTAssertNil(try backend.getTaskDetailPayload(publicID: localID), "precondition: tombstoned")

        // An edit newer than the delete wins LWW: it revives the row, not a phantom "applied".
        let revived = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Revived", updatedAt: "2050-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(revived["status"] as? String, "applied")
        let detail = try XCTUnwrap(
            backend.getTaskDetailPayload(publicID: localID), "a newer edit must resurrect the tombstoned row")
        XCTAssertEqual(detail["title"] as? String, "Revived")
        XCTAssertEqual(detail["id"] as? String, localID, "revival keeps the same public_id")
    }

    func testUploadUpsertOnTombstonedRowStaysDeletedWhenEditIsOlder() throws {
        let backend = try makeBackend()
        let localID = "66666666-6666-6666-6666-666666666666"
        _ = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Live", updatedAt: "2030-01-01T00:00:00.000Z")
            ]))
        _ = try result(
            of: backend.upload(operations: [
                deleteOp(localID: localID, updatedAt: "2040-01-01T00:00:00.000Z")
            ]))

        // An edit older than the delete loses LWW: stale, and the row stays deleted (no phantom apply).
        let stale = try result(
            of: backend.upload(operations: [
                upsertOp(localID: localID, title: "Too late", updatedAt: "2035-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(stale["status"] as? String, "stale")
        XCTAssertNil(try backend.getTaskDetailPayload(publicID: localID), "the row stays deleted")
    }

    func testUploadFailsClosedOnMissingOrUnknownOperation() throws {
        let backend = try makeBackend()
        let response = try backend.upload(operations: [
            ["type": "tasks", "localId": "x", "data": [:]],  // no operation
            ["operation": "destroy", "type": "tasks", "localId": "y"],  // unknown
        ])
        let results = try XCTUnwrap(response["results"] as? [[String: Any]])
        XCTAssertEqual(results.allSatisfy { ($0["status"] as? String) == "rejected" }, true)
        XCTAssertEqual(results[0]["code"] as? String, "missing_operation")
        XCTAssertEqual(results[1]["code"] as? String, "unknown_operation")
    }

    // MARK: - Helpers

    private func makeBackend() throws -> DemoServerSimulator {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-tests-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try DemoServerSimulator(databaseURL: url, seedData: DemoSeedData.generate())
    }

    private func upsertOp(localID: String, title: String, updatedAt: String = "2026-06-16T20:00:00.000Z")
        -> [String: Any]
    {
        [
            "operation": "upsert", "type": "tasks", "localId": localID, "updatedAt": updatedAt,
            "data": [
                "id": localID, "project_id": projectID, "author_id": authorID, "title": title,
                "description": "from offline", "state": ["id": "todo"],
                "created_at": updatedAt, "updated_at": updatedAt,
            ],
        ]
    }

    private func deleteOp(localID: String, updatedAt: String) -> [String: Any] {
        ["operation": "delete", "type": "tasks", "localId": localID, "updatedAt": updatedAt]
    }

    private func result(of response: [String: Any]) throws -> [String: Any] {
        let results = try XCTUnwrap(response["results"] as? [[String: Any]])
        return try XCTUnwrap(results.first)
    }
}
