import Foundation
import SwiftData
import SwiftSync

@Syncable
@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var taskCount: Int
    var createdAt: Date
    var updatedAt: Date
    var tasks: [Task]

    init(
        id: String,
        name: String,
        taskCount: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        tasks: [Task] = []
    ) {
        self.id = id
        self.name = name
        self.taskCount = taskCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tasks = tasks
    }
}

@Syncable
@Model
final class User {
    @Attribute(.unique) var id: String
    var displayName: String
    @RemoteKey("role.id")
    var role: String
    @RemoteKey("role.label")
    var roleLabel: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String, displayName: String, role: String, roleLabel: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.roleLabel = roleLabel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class TaskStateOption {
    @Attribute(.unique) var id: String
    var label: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: String, label: String, sortOrder: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.label = label
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class UserRoleOption {
    @Attribute(.unique) var id: String
    var label: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: String, label: String, sortOrder: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.label = label
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class Task {
    @Attribute(.unique) var id: String

    var projectID: String

    var assigneeID: String?
    var authorID: String

    var title: String

    @RemoteKey("description")
    var descriptionText: String

    @RemoteKey("state.id")
    var state: String
    @RemoteKey("state.label")
    var stateLabel: String
    var createdAt: Date
    var updatedAt: Date
    var project: Project?

    var author: User?
    var assignee: User?

    @Relationship var reviewers: [User]
    @Relationship var watchers: [User]

    init(
        id: String = UUID().uuidString,
        projectID: String,
        assigneeID: String? = nil,
        authorID: String = "",
        title: String = "",
        descriptionText: String = "",
        state: String = "",
        stateLabel: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        project: Project? = nil,
        author: User? = nil,
        assignee: User? = nil,
        reviewers: [User] = [],
        watchers: [User] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.assigneeID = assigneeID
        self.authorID = authorID
        self.title = title
        self.descriptionText = descriptionText
        self.state = state
        self.stateLabel = stateLabel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.project = project
        self.author = author
        self.assignee = assignee
        self.reviewers = reviewers
        self.watchers = watchers
    }
}
