import Foundation
import SwiftData
import SwiftSync

@Syncable
@Model
public final class Project {
    @Attribute(.unique) public var id: String
    public var name: String
    public var taskCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var tasks: [Task]

    public init(
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
public final class User {
    @Attribute(.unique) public var id: String
    public var displayName: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, displayName: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
public final class TaskStateOption {
    @Attribute(.unique) public var id: String
    public var label: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, label: String, sortOrder: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.label = label
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
public final class Task {
    @Attribute(.unique) public var id: String

    public var projectID: String

    public var assigneeID: String?
    public var authorID: String

    public var title: String

    @RemoteKey("description")
    public var descriptionText: String?

    @RemoteKey("state.id")
    public var state: String
    @RemoteKey("state.label")
    public var stateLabel: String
    public var createdAt: Date
    public var updatedAt: Date

    @NotExport
    public var project: Project?

    @NotExport
    public var author: User?

    @NotExport
    public var assignee: User?

    @NotExport
    @Relationship
    public var reviewers: [User]

    @NotExport
    @Relationship
    public var watchers: [User]
    @Relationship(deleteRule: .cascade, inverse: \Item.task)
    public var items: [Item]

    public init(
        id: String = UUID().uuidString,
        projectID: String,
        assigneeID: String? = nil,
        authorID: String = "",
        title: String = "",
        descriptionText: String? = nil,
        state: String = "",
        stateLabel: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        project: Project? = nil,
        author: User? = nil,
        assignee: User? = nil,
        reviewers: [User] = [],
        watchers: [User] = [],
        items: [Item] = []
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
        self.items = items
    }
}

@Syncable
@Model
public final class Item {
    @Attribute(.unique) public var id: String
    public var taskID: String
    public var title: String
    public var position: Int
    public var createdAt: Date
    public var updatedAt: Date

    @NotExport
    public var task: Task?

    public init(
        id: String = UUID().uuidString,
        taskID: String = "",
        title: String = "",
        position: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        task: Task? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.task = task
    }
}
