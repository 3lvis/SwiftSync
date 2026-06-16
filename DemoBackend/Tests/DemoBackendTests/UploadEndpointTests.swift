import Foundation
import XCTest

@testable import DemoBackend

final class UploadEndpointTests: XCTestCase {
    private let projectID = DemoSeedData.SeedIDs.Projects.accountSecurity
    private let authorID = DemoSeedData.SeedIDs.Users.avaMartinez

    func testUploadInsertMintsDistinctRemoteIDAndIsIdempotent() throws {
        let backend = try makeBackend()
        let localID = "LOCAL-INSERT-1"
        let before = try backend.getProjectTasksPayload(projectID: projectID).count

        let first = try result(of: backend.upload(operations: [insertOp(localID: localID, title: "Offline task")]))
        XCTAssertEqual(first["status"] as? String, "applied")
        let remoteID = try XCTUnwrap(first["remoteId"] as? String)
        XCTAssertNotEqual(remoteID, localID, "the server mints its own remote id, distinct from localId")
        XCTAssertTrue(remoteID.hasPrefix("srv-"))

        let tasks = try backend.getProjectTasksPayload(projectID: projectID)
        XCTAssertEqual(tasks.count, before + 1)
        let inserted = try XCTUnwrap(tasks.first { ($0["id"] as? String) == localID })
        XCTAssertEqual(inserted["remote_id"] as? String, remoteID)

        // Retry the same insert (lost-response scenario): same remote id, no duplicate row.
        let retry = try result(of: backend.upload(operations: [insertOp(localID: localID, title: "Offline task")]))
        XCTAssertEqual(retry["remoteId"] as? String, remoteID)
        XCTAssertEqual(try backend.getProjectTasksPayload(projectID: projectID).count, before + 1)
    }

    func testUploadUpdateIsLastWriterWins() throws {
        let backend = try makeBackend()
        let localID = "LOCAL-UPDATE-1"
        let inserted = try result(of: backend.upload(operations: [
            insertOp(localID: localID, title: "Original", updatedAt: "2026-01-01T00:00:00.000Z")
        ]))
        let remoteID = try XCTUnwrap(inserted["remoteId"] as? String)

        // Older write loses: kept server state returned, title unchanged.
        let stale = try result(of: backend.upload(operations: [
            updateOp(remoteID: remoteID, localID: localID, title: "Stale edit", updatedAt: "2020-01-01T00:00:00.000Z")
        ]))
        XCTAssertEqual(stale["status"] as? String, "stale")
        let server = try XCTUnwrap(stale["server"] as? [String: Any])
        XCTAssertEqual(server["title"] as? String, "Original")

        // Newer write wins.
        let applied = try result(of: backend.upload(operations: [
            updateOp(remoteID: remoteID, localID: localID, title: "Fresh edit", updatedAt: "2030-01-01T00:00:00.000Z")
        ]))
        XCTAssertEqual(applied["status"] as? String, "applied")
        let detail = try XCTUnwrap(backend.getTaskDetailPayload(taskID: localID))
        XCTAssertEqual(detail["title"] as? String, "Fresh edit")
    }

    func testUploadDeleteTombstonesAndHidesFromReads() throws {
        let backend = try makeBackend()
        let localID = "LOCAL-DELETE-1"
        let inserted = try result(of: backend.upload(operations: [insertOp(localID: localID, title: "Doomed")]))
        let remoteID = try XCTUnwrap(inserted["remoteId"] as? String)

        let deleted = try result(of: backend.upload(operations: [
            deleteOp(remoteID: remoteID, updatedAt: "2030-01-01T00:00:00.000Z")
        ]))
        XCTAssertEqual(deleted["status"] as? String, "applied")

        XCTAssertNil(try backend.getTaskDetailPayload(taskID: localID), "tombstoned row is hidden from detail")
        XCTAssertFalse(
            try backend.getProjectTasksPayload(projectID: projectID).contains { ($0["id"] as? String) == localID },
            "tombstoned row is hidden from the list")
    }

    func testUploadFailsClosedOnMissingOrUnknownOperation() throws {
        let backend = try makeBackend()
        let response = try backend.upload(operations: [
            ["type": "tasks", "localId": "x", "data": [:]],  // no operation
            ["operation": "destroy", "type": "tasks", "remoteId": "y"],  // unknown
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

    private func insertOp(localID: String, title: String, updatedAt: String = "2026-06-16T20:00:00.000Z")
        -> [String: Any]
    {
        [
            "operation": "insert", "type": "tasks", "localId": localID, "updatedAt": updatedAt,
            "data": [
                "project_id": projectID, "author_id": authorID, "title": title,
                "description": "from offline", "state": ["id": "todo"],
                "created_at": updatedAt, "updated_at": updatedAt,
            ],
        ]
    }

    private func updateOp(remoteID: String, localID: String, title: String, updatedAt: String)
        -> [String: Any]
    {
        [
            "operation": "update", "type": "tasks", "remoteId": remoteID, "updatedAt": updatedAt,
            "data": [
                "id": localID, "project_id": projectID, "author_id": authorID, "title": title,
                "description": "edited", "state": ["id": "todo"],
                "created_at": "2026-01-01T00:00:00.000Z", "updated_at": updatedAt,
            ],
        ]
    }

    private func deleteOp(remoteID: String, updatedAt: String) -> [String: Any] {
        ["operation": "delete", "type": "tasks", "remoteId": remoteID, "updatedAt": updatedAt]
    }

    private func result(of response: [String: Any]) throws -> [String: Any] {
        let results = try XCTUnwrap(response["results"] as? [[String: Any]])
        return try XCTUnwrap(results.first)
    }
}
