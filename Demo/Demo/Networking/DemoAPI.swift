import Foundation

@MainActor
enum DemoNetworkScenario: String, CaseIterable, Identifiable {
    case fastStable
    case slowNetwork
    case flakyNetwork
    case offline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastStable:
            return "Fast Stable"
        case .slowNetwork:
            return "Slow Network"
        case .flakyNetwork:
            return "Flaky Network"
        case .offline:
            return "Offline"
        }
    }
}

enum DemoAPIError: LocalizedError {
    case offline
    case transient(endpoint: String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You are offline in this scenario preset."
        case let .transient(endpoint):
            return "Transient network failure while calling \(endpoint)."
        }
    }
}

@MainActor
protocol DemoAPIClient: AnyObject {
    var scenario: DemoNetworkScenario { get set }

    func getProjects() async throws -> [[String: Any]]
    func getProjectTasks(projectID: String) async throws -> [[String: Any]]
    func getUsers() async throws -> [[String: Any]]
    func getUserTasks(userID: String) async throws -> [[String: Any]]
    func getTaskDetail(taskID: String) async throws -> [String: Any]?
    func getTaskComments(taskID: String) async throws -> [[String: Any]]
    func getTags() async throws -> [[String: Any]]
    func getTagTasks(tagID: String) async throws -> [[String: Any]]
}

@MainActor
final class FakeDemoAPIClient: DemoAPIClient {
    var scenario: DemoNetworkScenario

    private let seedData: DemoSeedData
    private var requestCounter = 0

    init(scenario: DemoNetworkScenario = .fastStable, seedData: DemoSeedData = .generate()) {
        self.scenario = scenario
        self.seedData = seedData
    }

    func getProjects() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /projects")
        return seedData.projects.map { project in
            [
                "id": project.id,
                "name": project.name,
                "status": project.status,
                "updated_at": iso8601(project.updatedAt)
            ]
        }
    }

    func getProjectTasks(projectID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /projects/{id}/tasks")
        return seedData.tasks
            .filter { $0.projectID == projectID }
            .map(taskPayload(from:))
    }

    func getUsers() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /users")
        return seedData.users.map { user in
            [
                "id": user.id,
                "display_name": user.displayName,
                "avatar_seed": user.avatarSeed,
                "role": user.role,
                "updated_at": iso8601(user.updatedAt)
            ]
        }
    }

    func getUserTasks(userID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /users/{id}/tasks")
        return seedData.tasks
            .filter { $0.assigneeID == userID }
            .map(taskPayload(from:))
    }

    func getTaskDetail(taskID: String) async throws -> [String: Any]? {
        try await networkGate(endpoint: "GET /tasks/{id}")
        guard let task = seedData.tasks.first(where: { $0.id == taskID }) else {
            return nil
        }
        return taskPayload(from: task)
    }

    func getTaskComments(taskID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /tasks/{id}/comments")
        return seedData.comments
            .filter { $0.taskID == taskID }
            .map { comment in
                [
                    "id": comment.id,
                    "task_id": comment.taskID,
                    "author_user_id": comment.authorUserID,
                    "body": comment.body,
                    "created_at": iso8601(comment.createdAt),
                    "updated_at": iso8601(comment.updatedAt)
                ]
            }
    }

    func getTags() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /tags")
        return seedData.tags.map { tag in
            [
                "id": tag.id,
                "name": tag.name,
                "color_hex": tag.colorHex,
                "updated_at": iso8601(tag.updatedAt)
            ]
        }
    }

    func getTagTasks(tagID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /tags/{id}/tasks")
        return seedData.tasks
            .filter { $0.tagIDs.contains(tagID) }
            .map(taskPayload(from:))
    }

    private func taskPayload(from task: DemoSeedData.SeedTask) -> [String: Any] {
        [
            "id": task.id,
            "project_id": task.projectID,
            "assignee_id": jsonOrNull(task.assigneeID),
            "title": task.title,
            "description": task.descriptionText,
            "state": task.state,
            "priority": task.priority,
            "due_date": jsonOrNull(task.dueDate.map(iso8601)),
            "tag_ids": task.tagIDs,
            "updated_at": iso8601(task.updatedAt)
        ]
    }

    private func jsonOrNull<T>(_ value: T?) -> Any {
        if let value {
            return value
        }
        return NSNull()
    }

    private func networkGate(endpoint: String) async throws {
        requestCounter += 1
        let callIndex = requestCounter

        switch scenario {
        case .offline:
            throw DemoAPIError.offline
        case .flakyNetwork:
            if ((callIndex + endpoint.count) % 5) == 0 {
                throw DemoAPIError.transient(endpoint: endpoint)
            }
        case .fastStable, .slowNetwork:
            break
        }

        let baseDelayMS: UInt64
        switch scenario {
        case .fastStable:
            baseDelayMS = 150
        case .slowNetwork:
            baseDelayMS = 950
        case .flakyNetwork:
            baseDelayMS = 450
        case .offline:
            baseDelayMS = 0
        }

        let jitter = UInt64((stableHash(endpoint) + callIndex * 17) % 250)
        let delay = baseDelayMS + jitter
        try await _Concurrency.Task.sleep(nanoseconds: delay * 1_000_000)
    }

    private func stableHash(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { partial, scalar in
            (partial * 31 + Int(scalar.value)) % 10_000
        }
    }

    private static let apiDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func iso8601(_ date: Date) -> String {
        Self.apiDateFormatter.string(from: date)
    }
}

struct DemoSeedData {
    struct SeedProject {
        let id: String
        let name: String
        let status: String
        let updatedAt: Date
    }

    struct SeedUser {
        let id: String
        let displayName: String
        let avatarSeed: String
        let role: String
        let updatedAt: Date
    }

    struct SeedTag {
        let id: String
        let name: String
        let colorHex: String
        let updatedAt: Date
    }

    struct SeedTask {
        let id: String
        let projectID: String
        let assigneeID: String?
        let title: String
        let descriptionText: String
        let state: String
        let priority: Int
        let dueDate: Date?
        let tagIDs: [String]
        let updatedAt: Date
    }

    struct SeedComment {
        let id: String
        let taskID: String
        let authorUserID: String
        let body: String
        let createdAt: Date
        let updatedAt: Date
    }

    let projects: [SeedProject]
    let users: [SeedUser]
    let tags: [SeedTag]
    let tasks: [SeedTask]
    let comments: [SeedComment]

    static func generate() -> DemoSeedData {
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
