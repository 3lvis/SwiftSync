import Foundation
import SwiftData
import SwiftSync

@Syncable
@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var status: String
    var serverUpdatedAt: Date
    var tasks: [Task]

    init(
        id: String,
        name: String,
        status: String,
        serverUpdatedAt: Date,
        tasks: [Task] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.serverUpdatedAt = serverUpdatedAt
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
    var serverUpdatedAt: Date
    var assignedTasks: [Task]
    var authoredComments: [Comment]

    init(
        id: String,
        displayName: String,
        avatarSeed: String,
        role: String,
        serverUpdatedAt: Date,
        assignedTasks: [Task] = [],
        authoredComments: [Comment] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarSeed = avatarSeed
        self.role = role
        self.serverUpdatedAt = serverUpdatedAt
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
    var serverUpdatedAt: Date
    var tasks: [Task]

    init(
        id: String,
        name: String,
        colorHex: String,
        serverUpdatedAt: Date,
        tasks: [Task] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.serverUpdatedAt = serverUpdatedAt
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
    var serverUpdatedAt: Date
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
        serverUpdatedAt: Date,
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
        self.serverUpdatedAt = serverUpdatedAt
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
    var serverUpdatedAt: Date
    var task: Task?
    var author: User?

    init(
        id: String,
        taskID: String,
        authorUserID: String,
        body: String,
        createdAt: Date,
        serverUpdatedAt: Date,
        task: Task? = nil,
        author: User? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.authorUserID = authorUserID
        self.body = body
        self.createdAt = createdAt
        self.serverUpdatedAt = serverUpdatedAt
        self.task = task
        self.author = author
    }
}

extension Task: ParentScopedModel {
    typealias SyncParent = Project
    static var parentRelationship: ReferenceWritableKeyPath<Task, Project?> { \.project }
    static var syncIdentityPolicy: SyncIdentityPolicy { .global }
}

extension Task: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        var changed = false

        if payload.contains("project_id") {
            let projects = try context.fetch(FetchDescriptor<Project>())
            let projectByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
            let nextProjectID: String = try payload.required(String.self, for: "project_id")
            let nextProject = projectByID[nextProjectID]
            if project?.id != nextProject?.id {
                project = nextProject
                changed = true
            }
        }

        if payload.contains("assignee_id") {
            let users = try context.fetch(FetchDescriptor<User>())
            let userByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            let nextAssigneeID: String? = payload.value(for: "assignee_id")
            let nextAssignee = nextAssigneeID.flatMap { userByID[$0] }
            if assignee?.id != nextAssignee?.id {
                assignee = nextAssignee
                changed = true
            }
        }

        if payload.contains("tag_ids") {
            let tagsInStore = try context.fetch(FetchDescriptor<Tag>())
            let tagsByID = Dictionary(uniqueKeysWithValues: tagsInStore.map { ($0.id, $0) })
            let desiredTagIDs: [String]
            if let ids: [String] = payload.value(for: "tag_ids") {
                desiredTagIDs = ids
            } else {
                desiredTagIDs = []
            }
            let desiredTags = desiredTagIDs.compactMap { tagsByID[$0] }
            if tags.map(\.id) != desiredTags.map(\.id) {
                tags = desiredTags
                changed = true
            }
        }

        return changed
    }
}

extension Comment: ParentScopedModel {
    typealias SyncParent = Task
    static var parentRelationship: ReferenceWritableKeyPath<Comment, Task?> { \.task }
    static var syncIdentityPolicy: SyncIdentityPolicy { .global }
}

extension Comment: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        var changed = false

        if payload.contains("task_id") {
            let tasks = try context.fetch(FetchDescriptor<Task>())
            let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let nextTaskID: String = try payload.required(String.self, for: "task_id")
            let nextTask = taskByID[nextTaskID]
            if task?.id != nextTask?.id {
                task = nextTask
                changed = true
            }
        }

        if payload.contains("author_user_id") {
            let users = try context.fetch(FetchDescriptor<User>())
            let userByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            let nextAuthorID: String = try payload.required(String.self, for: "author_user_id")
            let nextAuthor = userByID[nextAuthorID]
            if author?.id != nextAuthor?.id {
                author = nextAuthor
                changed = true
            }
        }

        return changed
    }
}
