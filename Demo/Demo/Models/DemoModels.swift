import Foundation
import SwiftData
import SwiftSync

@Syncable
@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var status: String
    var updatedAt: Date
    var tasks: [Task]

    init(
        id: String,
        name: String,
        status: String,
        updatedAt: Date,
        tasks: [Task] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.updatedAt = updatedAt
        self.tasks = tasks
    }
}

@Syncable
@Model
final class User {
    @Attribute(.unique) var id: String
    var displayName: String
    var role: String
    var updatedAt: Date
    var assignedTasks: [Task]
    var authoredComments: [Comment]

    init(
        id: String,
        displayName: String,
        role: String,
        updatedAt: Date,
        assignedTasks: [Task] = [],
        authoredComments: [Comment] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.updatedAt = updatedAt
        self.assignedTasks = assignedTasks
        self.authoredComments = authoredComments
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

    var title: String

    @RemoteKey("description")
    var descriptionText: String

    var state: String
    var priority: Int
    var updatedAt: Date
    var project: Project?
    var assignee: User?
    var tags: [Tag]
    var comments: [Comment]

    init(
        id: String,
        projectID: String,
        assigneeID: String?,
        title: String,
        descriptionText: String,
        state: String,
        priority: Int,
        updatedAt: Date,
        project: Project? = nil,
        assignee: User? = nil,
        tags: [Tag] = [],
        comments: [Comment] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.assigneeID = assigneeID
        self.title = title
        self.descriptionText = descriptionText
        self.state = state
        self.priority = priority
        self.updatedAt = updatedAt
        self.project = project
        self.assignee = assignee
        self.tags = tags
        self.comments = comments
    }
}

@Syncable
@Model
final class Comment {
    @Attribute(.unique) var id: String

    var taskID: String

    var authorUserID: String

    var body: String
    var createdAt: Date
    var task: Task?

    var authorUser: User?

    init(
        id: String,
        taskID: String,
        authorUserID: String,
        body: String,
        createdAt: Date,
        task: Task? = nil,
        authorUser: User? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.authorUserID = authorUserID
        self.body = body
        self.createdAt = createdAt
        self.task = task
        self.authorUser = authorUser
    }
}
