import SwiftData
import SwiftSync
import XCTest

@Syncable
@Model
final class ConvertibleDraftUser {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// A consumer's plain Codable DTO — conforms to `SyncPayloadConvertible` with **zero** sync mapping code.
private struct DraftUserPayload: Codable, Sendable, SyncPayloadConvertible {
    let id: Int
    let name: String
}

final class SyncPayloadConvertibleTests: XCTestCase {
    func testEncodableConformanceDerivesPayloadDictionaryWithNoHandMapping() {
        let dictionary = DraftUserPayload(id: 7, name: "Bo").toSyncPayloadDictionary()
        XCTAssertEqual(dictionary["id"] as? Int, 7)
        XCTAssertEqual(dictionary["name"] as? String, "Bo")
    }

    @MainActor
    func testCodableDTOSyncsWithZeroMapping() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ConvertibleDraftUser.self, configurations: configuration)
        let syncContainer = SyncContainer(container)

        try await syncContainer.sync(payload: [DraftUserPayload(id: 1, name: "Ada")], as: ConvertibleDraftUser.self)

        let rows = try syncContainer.mainContext.fetch(FetchDescriptor<ConvertibleDraftUser>())
        XCTAssertEqual(rows.map(\.name), ["Ada"])
    }
}
