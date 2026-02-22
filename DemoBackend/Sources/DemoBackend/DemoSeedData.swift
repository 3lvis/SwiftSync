import Foundation

public struct DemoSeedData {
    public struct SeedProject: Sendable {
        public let id: String
        public let name: String
        public let status: String
        public let updatedAt: Date

        public init(id: String, name: String, status: String, updatedAt: Date) {
            self.id = id
            self.name = name
            self.status = status
            self.updatedAt = updatedAt
        }
    }

    public struct SeedUser: Sendable {
        public let id: String
        public let displayName: String
        public let avatarSeed: String
        public let role: String
        public let updatedAt: Date

        public init(id: String, displayName: String, avatarSeed: String, role: String, updatedAt: Date) {
            self.id = id
            self.displayName = displayName
            self.avatarSeed = avatarSeed
            self.role = role
            self.updatedAt = updatedAt
        }
    }

    public struct SeedTag: Sendable {
        public let id: String
        public let name: String
        public let colorHex: String
        public let updatedAt: Date

        public init(id: String, name: String, colorHex: String, updatedAt: Date) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.updatedAt = updatedAt
        }
    }

    public struct SeedTask: Sendable {
        public let id: String
        public let projectID: String
        public let assigneeID: String?
        public let title: String
        public let descriptionText: String
        public let state: String
        public let priority: Int
        public let dueDate: Date?
        public let tagIDs: [String]
        public let updatedAt: Date

        public init(
            id: String,
            projectID: String,
            assigneeID: String?,
            title: String,
            descriptionText: String,
            state: String,
            priority: Int,
            dueDate: Date?,
            tagIDs: [String],
            updatedAt: Date
        ) {
            self.id = id
            self.projectID = projectID
            self.assigneeID = assigneeID
            self.title = title
            self.descriptionText = descriptionText
            self.state = state
            self.priority = priority
            self.dueDate = dueDate
            self.tagIDs = tagIDs
            self.updatedAt = updatedAt
        }
    }

    public struct SeedComment: Sendable {
        public let id: String
        public let taskID: String
        public let authorUserID: String
        public let body: String
        public let createdAt: Date
        public let updatedAt: Date

        public init(id: String, taskID: String, authorUserID: String, body: String, createdAt: Date, updatedAt: Date) {
            self.id = id
            self.taskID = taskID
            self.authorUserID = authorUserID
            self.body = body
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    public let projects: [SeedProject]
    public let users: [SeedUser]
    public let tags: [SeedTag]
    public let tasks: [SeedTask]
    public let comments: [SeedComment]

    public init(
        projects: [SeedProject],
        users: [SeedUser],
        tags: [SeedTag],
        tasks: [SeedTask],
        comments: [SeedComment]
    ) {
        self.projects = projects
        self.users = users
        self.tags = tags
        self.tasks = tasks
        self.comments = comments
    }

    public static func generate() -> DemoSeedData {
        let baseDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

        let statuses = ["active", "onTrack", "atRisk", "blocked"]
        let roles = ["Engineer", "Designer", "PM", "QA", "Ops"]
        let taskStates = ["todo", "inProgress", "done"]

        var projects: [SeedProject] = []
        for index in 1...30 {
            projects.append(
                SeedProject(
                    id: "project-\(index)",
                    name: "Project \(index)",
                    status: statuses[index % statuses.count],
                    updatedAt: baseDate.addingTimeInterval(TimeInterval(index * 90))
                )
            )
        }

        var users: [SeedUser] = []
        for index in 1...40 {
            users.append(
                SeedUser(
                    id: "user-\(index)",
                    displayName: "User \(index)",
                    avatarSeed: "seed-\(index)",
                    role: roles[index % roles.count],
                    updatedAt: baseDate.addingTimeInterval(TimeInterval(index * 75))
                )
            )
        }

        var tags: [SeedTag] = []
        for index in 1...50 {
            let color = String(format: "#%06X", (index * 654321) % 0xFFFFFF)
            tags.append(
                SeedTag(
                    id: "tag-\(index)",
                    name: "tag-\(index)",
                    colorHex: color,
                    updatedAt: baseDate.addingTimeInterval(TimeInterval(index * 42))
                )
            )
        }

        var tasks: [SeedTask] = []
        for index in 1...300 {
            let projectIndex = ((index - 1) % projects.count) + 1
            let assignee: String?
            if index % 7 == 0 {
                assignee = nil
            } else {
                assignee = "user-\(((index * 3) % users.count) + 1)"
            }

            let dueDate: Date?
            if index % 6 == 0 {
                dueDate = nil
            } else {
                dueDate = baseDate.addingTimeInterval(TimeInterval(index * 9_000))
            }

            let tagCount = (index % 3) + 1
            let tagIDs = (0..<tagCount).map { offset in
                "tag-\(((index + offset * 11) % tags.count) + 1)"
            }

            tasks.append(
                SeedTask(
                    id: "task-\(index)",
                    projectID: "project-\(projectIndex)",
                    assigneeID: assignee,
                    title: "Task \(index)",
                    descriptionText: "Detailed description for task \(index). This is seeded fake backend content for staged sync demos.",
                    state: taskStates[index % taskStates.count],
                    priority: (index % 5) + 1,
                    dueDate: dueDate,
                    tagIDs: tagIDs,
                    updatedAt: baseDate.addingTimeInterval(TimeInterval(index * 120))
                )
            )
        }

        var comments: [SeedComment] = []
        for index in 1...2_000 {
            comments.append(
                SeedComment(
                    id: "comment-\(index)",
                    taskID: "task-\(((index - 1) % tasks.count) + 1)",
                    authorUserID: "user-\(((index * 5) % users.count) + 1)",
                    body: "Comment \(index): seeded for deterministic offline/read-only phase one coverage.",
                    createdAt: baseDate.addingTimeInterval(TimeInterval(index * 30)),
                    updatedAt: baseDate.addingTimeInterval(TimeInterval(index * 30 + 5))
                )
            )
        }

        return DemoSeedData(projects: projects, users: users, tags: tags, tasks: tasks, comments: comments)
    }
}
