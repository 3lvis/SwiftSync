import Foundation
import Testing
@testable import Core

struct SyncPayloadKeyStyleTests {
    @Test("SyncPayload default snake_case resolves acronym key projectID <- project_id")
    func defaultSnakeCaseResolvesAcronym() {
        let payload = SyncPayload(values: ["project_id": "p-1"])
        let value: String? = payload.value(for: "projectID")
        #expect(value == "p-1")
    }

    @Test("SyncPayload camelCase style resolves project_id lookup from projectId payload")
    func camelCaseStyleResolvesCamelPayload() {
        let payload = SyncPayload(
            values: ["projectId": "p-2"],
            keyStyle: .camelCase
        )
        let value: String? = payload.value(for: "project_id")
        #expect(value == "p-2")
    }
}
