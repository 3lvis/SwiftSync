import Foundation

public enum SwiftSyncFixtures {
    public static var usersPayload: [Any] {
        [
            [
                "id": 1,
                "full_name": "Ava Swift",
                "email": "ava@example.com",
                "created_at": "2026-02-18T00:00:00Z",
                "updated_at": "2026-02-18T00:00:00Z"
            ],
            [
                "id": 2,
                "full_name": "Noah Sync",
                "email": "noah@example.com",
                "created_at": "2026-02-18T01:00:00Z",
                "updated_at": "2026-02-18T01:00:00Z"
            ]
        ]
    }

    public static var emptyPayload: [Any] { [] }
}
