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
        case .fastStable: "Fast Stable"
        case .slowNetwork: "Slow Network"
        case .flakyNetwork: "Flaky Network"
        case .offline: "Offline"
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
final class FakeDemoAPIClient {
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

        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftSyncDemo-\(UUID().uuidString).sqlite")

        do {
            self.backend = try DemoServerSimulator(
                databaseURL: databaseURL,
                seedData: seedData ?? DemoSeedData.generate(),
                enableAmbientProjectMutationsOnRead: seedData == nil
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

    func getTaskStateOptions() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /task-state-options")
        return try backend.getTaskStateOptionsPayload()
    }

    func getUserRoleOptions() async throws -> [[String: Any]] {
        try await networkGate(endpoint: "GET /user-role-options")
        return try backend.getUserRoleOptionsPayload()
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

    func replaceTaskReviewers(taskID: String, reviewerIDs: [String]) async throws -> [String: Any]? {
        try await networkGate(endpoint: "PUT /tasks/{id}/reviewers")
        return try backend.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs)
    }

    func replaceTaskWatchers(taskID: String, watcherIDs: [String]) async throws -> [String: Any]? {
        try await networkGate(endpoint: "PUT /tasks/{id}/watchers")
        return try backend.replaceTaskWatchers(taskID: taskID, watcherIDs: watcherIDs)
    }

    func createTask(body: [String: Any]) async throws -> [String: Any] {
        try await networkGate(endpoint: "POST /tasks")
        return try backend.createTask(body: body)
    }

    func updateTask(taskID: String, body: [String: Any]) async throws -> [String: Any]? {
        try await networkGate(endpoint: "PUT /tasks/{id}")
        return try backend.updateTask(taskID: taskID, body: body)
    }

    func deleteTask(taskID: String) async throws {
        try await networkGate(endpoint: "DELETE /tasks/{id}")
        try backend.deleteTask(taskID: taskID)
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

        let baseDelayMS: UInt64 = switch scenario {
        case .fastStable: 150
        case .slowNetwork: 950
        case .flakyNetwork: 450
        case .offline: 0
        }

        let isMutation = endpoint.hasPrefix("PATCH ") || endpoint.hasPrefix("POST ") || endpoint.hasPrefix("PUT ") || endpoint.hasPrefix("DELETE ")
        let mutationExtra: UInt64 = isMutation ? (scenario == .fastStable ? 220 : scenario == .flakyNetwork ? 120 : 0) : 0
        let hash = endpoint.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 10_000 }
        let jitter = UInt64((hash + callIndex * 17) % 250)
        try await _Concurrency.Task.sleep(nanoseconds: (baseDelayMS + jitter + mutationExtra) * 1_000_000)
    }

}
