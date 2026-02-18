import XCTest
import SwiftData
import SwiftSyncCore
import SwiftSyncSwiftData

@Model
final class RuntimeUser {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

final class SwiftSyncRuntimeTests: XCTestCase {
    @MainActor
    func testSyncStubDoesNotThrow() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RuntimeUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [["id": 1, "name": "Ava"]]

        try await SwiftSync.sync(payload: payload, as: RuntimeUser.self, in: context)
    }
}
