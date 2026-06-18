import Foundation
import XCTest

@testable import DemoBackend

final class UploadEndpointTests: XCTestCase {
    private let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
    private let authorID = DemoSeedData.SeedIDs.Users.avaMartinez

    func testUploadUpsertCreatesThenUpdatesIdempotently() throws {
        let backend = try makeBackend()
        let id = "LOCAL-UPSERT-1"
        let before = try backend.getProjectTasksPayload(projectID: projectID).count

        let first = try result(of: backend.upload(operations: [upsertOp(id: id, title: "Offline task")]))
        XCTAssertEqual(first["status"] as? String, "applied")
        XCTAssertEqual(first["id"] as? String, id)

        let tasks = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertEqual(tasks.count, before + 1)
        let inserted = try XCTUnwrap(tasks.first { ($0["id"] as? String) == id })
        // Single-id model: the row's own id is its canonical server id, echoed back as remote_id.
        XCTAssertEqual(inserted["remote_id"] as? String, id)

        // Re-upsert the same id (lost-response retry): converged, no duplicate row. The identical
        // updatedAt loses the LWW tie (server wins ties), so the resend is a no-op marked "stale" —
        // not a failure, and not a second row.
        let retry = try result(of: backend.upload(operations: [upsertOp(id: id, title: "Offline task")]))
        XCTAssertNotEqual(retry["status"] as? String, "rejected")
        XCTAssertEqual(try backend.getProjectTasksPayload(projectID: projectID).count, before + 1)
    }

    func testUploadUpsertIsLastWriterWins() throws {
        let backend = try makeBackend()
        let id = "LOCAL-UPSERT-LWW-1"
        _ = try result(
            of: backend.upload(operations: [
                upsertOp(id: id, title: "Original", updatedAt: "2026-01-01T00:00:00.000Z")
            ]))

        // Older write loses: kept server state returned, title unchanged.
        let stale = try result(
            of: backend.upload(operations: [
                upsertOp(id: id, title: "Stale edit", updatedAt: "2020-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(stale["status"] as? String, "stale")
        let server = try XCTUnwrap(stale["server"] as? [String: Any])
        XCTAssertEqual(server["title"] as? String, "Original")

        // Newer write wins.
        let applied = try result(
            of: backend.upload(operations: [
                upsertOp(id: id, title: "Fresh edit", updatedAt: "2030-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(applied["status"] as? String, "applied")
        let detail = try XCTUnwrap(backend.getTaskDetailPayload(taskID: id))
        XCTAssertEqual(detail["title"] as? String, "Fresh edit")
    }

    func testUploadDeleteTombstonesAndHidesFromReads() throws {
        let backend = try makeBackend()
        let id = "LOCAL-DELETE-1"
        _ = try result(of: backend.upload(operations: [upsertOp(id: id, title: "Doomed")]))

        let deleted = try result(
            of: backend.upload(operations: [
                deleteOp(id: id, updatedAt: "2030-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(deleted["status"] as? String, "applied")

        XCTAssertNil(try backend.getTaskDetailPayload(taskID: id), "tombstoned row is hidden from detail")
        XCTAssertFalse(
            try backend.getProjectTasksPayload(projectID: projectID).contains { ($0["id"] as? String) == id },
            "tombstoned row is hidden from the list")
    }

    func testUploadDeleteIsLastWriterWins() throws {
        let backend = try makeBackend()
        let id = "LOCAL-DELETE-LWW-1"
        _ = try result(
            of: backend.upload(operations: [
                upsertOp(id: id, title: "Live", updatedAt: "2030-01-01T00:00:00.000Z")
            ]))

        // A delete older than the server's version must lose: stale + server state, not a tombstone.
        let stale = try result(
            of: backend.upload(operations: [
                deleteOp(id: id, updatedAt: "2020-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(stale["status"] as? String, "stale")
        XCTAssertNotNil(stale["server"] as? [String: Any])
        XCTAssertNotNil(
            try backend.getTaskDetailPayload(taskID: id), "a stale delete must not tombstone the row")

        // A newer delete wins.
        let applied = try result(
            of: backend.upload(operations: [
                deleteOp(id: id, updatedAt: "2040-01-01T00:00:00.000Z")
            ]))
        XCTAssertEqual(applied["status"] as? String, "applied")
        XCTAssertNil(try backend.getTaskDetailPayload(taskID: id))
    }

    func testUploadFailsClosedOnMissingOrUnknownOperation() throws {
        let backend = try makeBackend()
        let response = try backend.upload(operations: [
            ["type": "tasks", "id": "x", "data": [:]],  // no operation
            ["operation": "destroy", "type": "tasks", "id": "y"],  // unknown
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

    private func upsertOp(id: String, title: String, updatedAt: String = "2026-06-16T20:00:00.000Z")
        -> [String: Any]
    {
        [
            "operation": "upsert", "type": "tasks", "id": id, "updatedAt": updatedAt,
            "data": [
                "id": id, "project_id": projectID, "author_id": authorID, "title": title,
                "description": "from offline", "state": ["id": "todo"],
                "created_at": updatedAt, "updated_at": updatedAt,
            ],
        ]
    }

    private func deleteOp(id: String, updatedAt: String) -> [String: Any] {
        ["operation": "delete", "type": "tasks", "id": id, "updatedAt": updatedAt]
    }

    private func result(of response: [String: Any]) throws -> [String: Any] {
        let results = try XCTUnwrap(response["results"] as? [[String: Any]])
        return try XCTUnwrap(results.first)
    }
}
