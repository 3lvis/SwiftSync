import SwiftData
import SwiftSync
import XCTest

final class SyncJSONTests: XCTestCase {
    func testRoundTripsAStructuredDictionary() throws {
        let json = try SyncJSON(dictionary: [
            "id": 7,
            "full_name": "Ada",
            "active": true,
            "score": 3.5,
            "tags": ["a", "b"],
            "nested": ["k": "v"],
            "cleared": NSNull(),
        ])
        let dict = json.toSyncPayloadDictionary()

        XCTAssertEqual(dict["id"] as? Int, 7)
        XCTAssertEqual(dict["full_name"] as? String, "Ada")
        XCTAssertEqual(dict["active"] as? Bool, true)
        XCTAssertEqual(dict["score"] as? Double, 3.5)
        XCTAssertEqual(dict["tags"] as? [String], ["a", "b"])
        XCTAssertEqual((dict["nested"] as? [String: Any])?["k"] as? String, "v")
        XCTAssertTrue(dict["cleared"] is NSNull, "explicit null is preserved (so a sync can clear)")
    }

    func testKeyedAccessors() throws {
        let json = try SyncJSON(dictionary: [
            "project_id": "P1",
            "items": [["id": "i1"], ["id": "i2"]],
        ])
        XCTAssertEqual(json.string("project_id"), "P1")
        XCTAssertEqual(json.objectArray("items")?.count, 2)
        XCTAssertEqual(json.objectArray("items")?.first?.string("id"), "i1")
    }

    @MainActor
    func testSyncsAsAPayloadConvertibleValue() async throws {
        let container = try SyncContainer(for: User.self, configurations: .init(isStoredInMemoryOnly: true))
        try await container.sync(payload: [SyncJSON(dictionary: ["id": 1, "full_name": "Ada"])], as: User.self)

        let users = try container.mainContext.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.map(\.fullName), ["Ada"])
    }
}
