import Foundation
import DemoBackend

typealias DemoSeedData = DemoBackend.DemoSeedData
typealias DemoServerSimulator = DemoBackend.DemoServerSimulator

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
    func getTaskDetail(taskID: String) async throws -> [String: Any]?
    func getTaskComments(taskID: String) async throws -> [[String: Any]]
    func getTags() async throws -> [[String: Any]]
    func getTagTasks(tagID: String) async throws -> [[String: Any]]

    func patchTaskDescription(taskID: String, descriptionText: String) async throws -> [String: Any]?
    func patchTaskState(taskID: String, state: String) async throws -> [String: Any]?
    func patchTaskAssignee(taskID: String, assigneeID: String?) async throws -> [String: Any]?
    func replaceTaskTags(taskID: String, tagIDs: [String]) async throws -> [String: Any]?

    func createTask(
        projectID: String,
        title: String,
        descriptionText: String,
        state: String,
        assigneeID: String?,
        tagIDs: [String]
    ) async throws -> [String: Any]
    func deleteTask(taskID: String) async throws

    func createTaskComment(taskID: String, authorUserID: String, body: String) async throws -> [String: Any]
    func deleteTaskComment(commentID: String) async throws
}

@MainActor
final class FakeDemoAPIClient: DemoAPIClient {
    var scenario: DemoNetworkScenario

    private let backend: DemoServerSimulator
    private var requestCounter = 0

    init(
        scenario: DemoNetworkScenario = .fastStable,
        seedData: DemoSeedData? = nil,
        backend: DemoServerSimulator? = nil
    ) {
        self.scenario = scenario
        if let backend {
            self.backend = backend
            return
        }

        let databaseURL = if seedData == nil {
            Self.defaultBackendDatabaseURL()
        } else {
            Self.temporaryBackendDatabaseURL()
        }

        do {
            if seedData == nil {
                try Self.removeBackendStoreFiles(at: databaseURL)
            }
            self.backend = try DemoServerSimulator(
                databaseURL: databaseURL,
                seedData: seedData ?? DemoSeedData.generate()
            )
        } catch {
            fatalError("Failed to initialize fake demo backend: \(error)")
        }
    }

    func getProjects() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /projects")
        return try backend.getProjectsPayload()
    }

    func getProjectTasks(projectID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /projects/{id}/tasks")
        return try backend.getProjectTasksPayload(projectID: projectID)
    }

    func getUsers() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /users")
        return try backend.getUsersPayload()
    }

    func getTaskDetail(taskID: String) async throws -> [String: Any]? {
        try await networkGate(endpoint: "GET /tasks/{id}")
        return try backend.getTaskDetailPayload(taskID: taskID)
    }

    func getTaskComments(taskID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /tasks/{id}/comments")
        return try backend.getTaskCommentsPayload(taskID: taskID)
    }

    func getTags() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /tags")
        return try backend.getTagsPayload()
    }

    func getTagTasks(tagID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /tags/{id}/tasks")
        return try backend.getTagTasksPayload(tagID: tagID)
    }

    func patchTaskDescription(taskID: String, descriptionText: String) async throws -> [String: Any]? {
        try await networkGate(endpoint: "PATCH /tasks/{id}/description")
        return try backend.patchTaskDescription(taskID: taskID, descriptionText: descriptionText)
    }

    func patchTaskState(taskID: String, state: String) async throws -> [String: Any]? {
        try await networkGate(endpoint: "PATCH /tasks/{id} (state)")
        return try backend.patchTaskState(taskID: taskID, state: state)
    }

    func patchTaskAssignee(taskID: String, assigneeID: String?) async throws -> [String: Any]? {
        try await networkGate(endpoint: "PATCH /tasks/{id} (assignee_id)")
        return try backend.patchTaskAssignee(taskID: taskID, assigneeID: assigneeID)
    }

    func replaceTaskTags(taskID: String, tagIDs: [String]) async throws -> [String: Any]? {
        try await networkGate(endpoint: "PUT /tasks/{id}/tags")
        return try backend.replaceTaskTags(taskID: taskID, tagIDs: tagIDs)
    }

    func createTask(
        projectID: String,
        title: String,
        descriptionText: String,
        state: String,
        assigneeID: String?,
        tagIDs: [String]
    ) async throws -> [String: Any] {
        try await networkGate(endpoint: "POST /tasks")
        return try backend.createTask(
            projectID: projectID,
            title: title,
            descriptionText: descriptionText,
            state: state,
            assigneeID: assigneeID,
            tagIDs: tagIDs
        )
    }

    func deleteTask(taskID: String) async throws {
        try await networkGate(endpoint: "DELETE /tasks/{id}")
        try backend.deleteTask(taskID: taskID)
    }

    func createTaskComment(taskID: String, authorUserID: String, body: String) async throws -> [String: Any] {
        try await networkGate(endpoint: "POST /tasks/{id}/comments")
        return try backend.createComment(taskID: taskID, authorUserID: authorUserID, body: body)
    }

    func deleteTaskComment(commentID: String) async throws {
        try await networkGate(endpoint: "DELETE /comments/{id}")
        try backend.deleteComment(commentID: commentID)
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

    private static func defaultBackendDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("SwiftSyncDemo", isDirectory: true)
            .appendingPathComponent("fake-backend.sqlite")
    }

    private static func temporaryBackendDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftSyncDemo-FakeBackend-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private static func removeBackendStoreFiles(at databaseURL: URL) throws {
        let fm = FileManager.default
        let directory = databaseURL.deletingLastPathComponent()
        let baseName = databaseURL.lastPathComponent

        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        for suffix in ["", "-shm", "-wal"] {
            let fileURL = directory.appendingPathComponent(baseName + suffix)
            if fm.fileExists(atPath: fileURL.path) {
                try fm.removeItem(at: fileURL)
            }
        }
    }
}
