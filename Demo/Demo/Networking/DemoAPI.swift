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
    func getUserTasks(userID: String) async throws -> [[String: Any]]
    func getTaskDetail(taskID: String) async throws -> [String: Any]?
    func getTaskComments(taskID: String) async throws -> [[String: Any]]
    func getTags() async throws -> [[String: Any]]
    func getTagTasks(tagID: String) async throws -> [[String: Any]]
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

    func getUserTasks(userID: String) async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /users/{id}/tasks")
        return try backend.getUserTasksPayload(userID: userID)
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
}
