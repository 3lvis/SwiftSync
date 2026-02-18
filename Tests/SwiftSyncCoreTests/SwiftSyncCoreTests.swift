import Testing
@testable import SwiftSyncCore

struct SwiftSyncCoreTests {
    @Test("SyncPayload supports id and remoteID conventions")
    func payloadIdentityConventions() throws {
        let payload = SyncPayload(values: ["id": 42])
        let remoteID: Int? = payload.value(for: "remoteID")
        #expect(remoteID == 42)
    }

    @Test("SyncPayload throws for missing required keys")
    func payloadRequiredThrows() {
        let payload = SyncPayload(values: [:])
        #expect(throws: SyncError.self) {
            let _: Int = try payload.required(Int.self, for: "id")
        }
    }
}
