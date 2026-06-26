import Foundation
import SwiftSync

// The JSON shapes the demo backend speaks over the wire. Each DTO is `Codable` (so `DemoAPI` decodes it
// straight from the response bytes) and `SyncPayloadConvertible` (so it syncs into the `@Model` with zero
// hand-mapping — SwiftSync derives the payload dictionary from `Encodable`). Property names + `CodingKeys`
// mirror the backend's snake_case wire keys; the model's `keyStyle`/`@RemoteKey` map them on the way in.

public struct TaskDTO: Codable, Sendable, SyncPayloadConvertible {
    public struct State: Codable, Sendable {
        public let id: String
        public let label: String
    }

    public struct Item: Codable, Sendable {
        public let id: String
        public let taskID: String
        public let title: String
        public let position: Int
        public let createdAt: Date
        public let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, position
            case taskID = "task_id"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    public let id: String
    public let projectID: String
    public let assigneeID: String?
    public let authorID: String
    public let title: String
    public let description: String?
    public let state: State
    public let reviewerIDs: [String]
    public let watcherIDs: [String]
    public let items: [Item]
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, state, items
        case projectID = "project_id"
        case assigneeID = "assignee_id"
        case authorID = "author_id"
        case reviewerIDs = "reviewer_ids"
        case watcherIDs = "watcher_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct ProjectDTO: Codable, Sendable, SyncPayloadConvertible {
    public let id: String
    public let name: String
    public let taskCount: Int
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case taskCount = "task_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct UserDTO: Codable, Sendable, SyncPayloadConvertible {
    public let id: String
    public let displayName: String
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct TaskStateOptionDTO: Codable, Sendable, SyncPayloadConvertible {
    public let id: String
    public let label: String
    public let sortOrder: Int
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, label
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
