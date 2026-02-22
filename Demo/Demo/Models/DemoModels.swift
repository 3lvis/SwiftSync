import Foundation
import SwiftData
import SwiftSync

@Syncable
@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    @RemoteKey("status.id")
    var status: String
    @RemoteKey("status.label")
    var statusLabel: String
    var taskCount: Int
    var updatedAt: Date
    var tasks: [Task]

    init(
        id: String,
        name: String,
        status: String,
        statusLabel: String,
        taskCount: Int = 0,
        updatedAt: Date,
        tasks: [Task] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.statusLabel = statusLabel
        self.taskCount = taskCount
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
    var updatedAt: Date
    @Relationship(inverse: \Task.assignee)
    var assignedTasks: [Task]
    @Relationship(inverse: \Task.reviewer)
    var reviewTasks: [Task]
    @Relationship(inverse: \Task.watchers)
    var watchedTasks: [Task]

    init(
        id: String,
        displayName: String,
        role: String,
        roleLabel: String,
        updatedAt: Date,
        assignedTasks: [Task] = [],
        reviewTasks: [Task] = [],
        watchedTasks: [Task] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.roleLabel = roleLabel
        self.updatedAt = updatedAt
        self.assignedTasks = assignedTasks
        self.reviewTasks = reviewTasks
        self.watchedTasks = watchedTasks
    }
}

@Syncable
@Model
final class TaskStateOption {
    @Attribute(.unique) var id: String
    var label: String
    var sortOrder: Int
    var updatedAt: Date

    init(id: String, label: String, sortOrder: Int, updatedAt: Date) {
        self.id = id
        self.label = label
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class Tag {
    @Attribute(.unique) var id: String
    var name: String
    var updatedAt: Date
    var tasks: [Task]

    init(
        id: String,
        name: String,
        updatedAt: Date,
        tasks: [Task] = []
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.tasks = tasks
    }
}

@Syncable
@Model
final class Task {
    @Attribute(.unique) var id: String

    var projectID: String

    var assigneeID: String?
    var reviewerID: String?

    var title: String

    @RemoteKey("description")
    var descriptionText: String

    @RemoteKey("state.id")
    var state: String
    @RemoteKey("state.label")
    var stateLabel: String
    var updatedAt: Date
    var project: Project?
    var assignee: User?
    var reviewer: User?
    var tags: [Tag]
    var watchers: [User]
    var comments: [Comment]

    init(
        id: String,
        projectID: String,
        assigneeID: String?,
        reviewerID: String?,
        title: String,
        descriptionText: String,
        state: String,
        stateLabel: String,
        updatedAt: Date,
        project: Project? = nil,
        assignee: User? = nil,
        reviewer: User? = nil,
        tags: [Tag] = [],
        watchers: [User] = [],
        comments: [Comment] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.assigneeID = assigneeID
        self.reviewerID = reviewerID
        self.title = title
        self.descriptionText = descriptionText
        self.state = state
        self.stateLabel = stateLabel
        self.updatedAt = updatedAt
        self.project = project
        self.assignee = assignee
        self.reviewer = reviewer
        self.tags = tags
        self.watchers = watchers
        self.comments = comments
    }
}

@Syncable
@Model
final class Comment {
    @Attribute(.unique) var id: String

    var taskID: String

    var authorUserID: String
    var authorName: String

    var body: String
    var createdAt: Date
    var task: Task?

    init(
        id: String,
        taskID: String,
        authorUserID: String,
        authorName: String,
        body: String,
        createdAt: Date,
        task: Task? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.authorUserID = authorUserID
        self.authorName = authorName
        self.body = body
        self.createdAt = createdAt
        self.task = task
    }
}
