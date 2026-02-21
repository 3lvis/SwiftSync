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
    var avatarSeed: String
    var role: String
    var updatedAt: Date
    var assignedTasks: [Task]
    var authoredComments: [Comment]

    init(
        id: String,
        displayName: String,
        avatarSeed: String,
        role: String,
        updatedAt: Date,
        assignedTasks: [Task] = [],
        authoredComments: [Comment] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarSeed = avatarSeed
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
    var colorHex: String
    var updatedAt: Date
    var tasks: [Task]

    init(
        id: String,
        name: String,
        colorHex: String,
        updatedAt: Date,
        tasks: [Task] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.updatedAt = updatedAt
        self.tasks = tasks
    }
}

@Syncable
@Model
final class Task {
    @Attribute(.unique) var id: String

    @RemoteKey("project_id")
    var projectID: String

    @RemoteKey("assignee_id")
    var assigneeID: String?

    var title: String

    @RemoteKey("description")
    var descriptionText: String

    var state: String
    var priority: Int
    var dueDate: Date?
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
        dueDate: Date?,
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
        self.dueDate = dueDate
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

    @RemoteKey("task_id")
    var taskID: String

    @RemoteKey("author_user_id")
    var authorUserID: String

    var body: String
    var createdAt: Date
    var updatedAt: Date
    var task: Task?

    @RemoteKey("author_user_id")
    var author: User?

    init(
        id: String,
        taskID: String,
        authorUserID: String,
        body: String,
        createdAt: Date,
        updatedAt: Date,
        task: Task? = nil,
        author: User? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.authorUserID = authorUserID
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.task = task
        self.author = author
    }
}

extension Task: ParentScopedModel {
    typealias SyncParent = Project
    static var parentRelationship: ReferenceWritableKeyPath<Task, Project?> { \.project }
    static var syncIdentityPolicy: SyncIdentityPolicy { .global }
}

extension Comment: ParentScopedModel {
    typealias SyncParent = Task
    static var parentRelationship: ReferenceWritableKeyPath<Comment, Task?> { \.task }
    static var syncIdentityPolicy: SyncIdentityPolicy { .global }
}
