import Foundation
import Testing
@testable import Core

struct SyncPayloadDeepPathTests {
    @Test("SyncPayload resolves deep path values from nested dictionaries")
    func resolvesDeepPathFromNestedValues() {
        let payload = SyncPayload(
            values: [
                "profile": [
                    "contact": [
                        "email": "deep@example.com"
                    ]
                ]
            ]
        )

        let value: String? = payload.value(for: "profile.contact.email")
        #expect(value == "deep@example.com")
        #expect(payload.contains("profile.contact.email"))
    }

    @Test("SyncPayload deep path detects explicit null")
    func deepPathDetectsExplicitNull() {
        let payload = SyncPayload(
            values: [
                "profile": [
                    "contact": [
                        "email": NSNull()
                    ]
                ]
            ]
        )

        let nullValue: NSNull? = payload.value(for: "profile.contact.email", as: NSNull.self)
        let stringValue: String? = payload.value(for: "profile.contact.email")

        #expect(payload.contains("profile.contact.email"))
        #expect(nullValue != nil)
        #expect(stringValue == nil)
    }

    @Test("SyncPayload camelCase mode transforms deep path segments")
    func camelCaseModeTransformsDeepPathSegments() {
        let payload = SyncPayload(
            values: [
                "profileData": [
                    "contactEmail": "camel@example.com"
                ]
            ],
            keyStyle: .camelCase
        )

        let value: String? = payload.value(for: "profile_data.contact_email")
        #expect(value == "camel@example.com")
        #expect(payload.contains("profile_data.contact_email"))
    }
}
