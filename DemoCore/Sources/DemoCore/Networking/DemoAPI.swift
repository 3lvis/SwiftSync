import DemoBackend
import Foundation

public typealias DemoSeedData = DemoBackend.DemoSeedData
public typealias DemoServerSimulator = DemoBackend.DemoServerSimulator

public enum DemoNetworkScenario: String, CaseIterable, Identifiable {
    case fastStable
    case slowNetwork
    case flakyNetwork
    case offline

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fastStable: "Fast Stable"
        case .slowNetwork: "Slow Network"
        case .flakyNetwork: "Flaky Network"
        case .offline: "Offline"
        }
    }
}

public enum DemoAPIError: LocalizedError {
    case offline
    case transient(endpoint: String)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .offline:
            return "You are offline in this scenario preset."
        case let .transient(endpoint):
            return "Transient network failure while calling \(endpoint)."
        case let .invalidPayload(message):
            return message
        }
    }
}

@MainActor
public final class FakeDemoAPIClient {
    public enum NetworkDelayMode {
        case scenarioDriven
        case disabled
    }

    public var scenario: DemoNetworkScenario

    private let backend: DemoServerSimulator
    private let networkDelayMode: NetworkDelayMode
    private var requestCounter = 0

    public init(
        scenario: DemoNetworkScenario = .fastStable,
        seedData: DemoSeedData? = nil,
        backend: DemoServerSimulator? = nil,
        networkDelayMode: NetworkDelayMode = .scenarioDriven
    ) {
        self.scenario = scenario
        self.networkDelayMode = networkDelayMode
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

    public func getProjects() async throws -> [DemoSyncPayload] {
        try await networkGate(endpoint: "GET /projects")
        return try backend.getProjectsPayload().map(Self.makePayload)
    }

    public func getProjectTasks(projectID: String) async throws -> [DemoSyncPayload] {
        try await networkGate(endpoint: "GET /projects/{id}/tasks")
        return try backend.getProjectTasksPayload(projectID: projectID).map(Self.makePayload)
    }

    public func getUsers() async throws -> [DemoSyncPayload] {
        try await networkGate(endpoint: "GET /users")
        return try backend.getUsersPayload().map(Self.makePayload)
    }

    public func getTaskDetail(taskID: String) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "GET /tasks/{id}")
        guard let payload = try backend.getTaskDetailPayload(taskID: taskID) else { return nil }
        return try Self.makePayload(payload)
    }

    public func getTaskStateOptions() async throws -> [DemoSyncPayload] {
        try await networkGate(endpoint: "GET /task-state-options")
        return try backend.getTaskStateOptionsPayload().map(Self.makePayload)
    }

    public func patchTaskState(taskID: String, state: String) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PATCH /tasks/{id} (state)")
        guard let payload = try backend.patchTaskState(taskID: taskID, state: state) else { return nil }
        return try Self.makePayload(payload)
    }

    public func patchTaskAssignee(taskID: String, assigneeID: String?) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PATCH /tasks/{id} (assignee_id)")
        guard let payload = try backend.patchTaskAssignee(taskID: taskID, assigneeID: assigneeID) else { return nil }
        return try Self.makePayload(payload)
    }

    public func replaceTaskReviewers(taskID: String, reviewerIDs: [String]) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PUT /tasks/{id}/reviewers")
        guard let payload = try backend.replaceTaskReviewers(taskID: taskID, reviewerIDs: reviewerIDs) else { return nil }
        return try Self.makePayload(payload)
    }

    public func replaceTaskWatchers(taskID: String, watcherIDs: [String]) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PUT /tasks/{id}/watchers")
        guard let payload = try backend.replaceTaskWatchers(taskID: taskID, watcherIDs: watcherIDs) else { return nil }
        return try Self.makePayload(payload)
    }

    public func createTask(body: DemoSyncPayload) async throws -> DemoSyncPayload {
        try await networkGate(endpoint: "POST /tasks")
        let created = try backend.createTask(body: body.toSyncPayloadDictionary())
        return try Self.makePayload(created)
    }

    public func updateTask(taskID: String, body: DemoSyncPayload) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PUT /tasks/{id}")
        let updated = try backend.updateTask(taskID: taskID, body: body.toSyncPayloadDictionary())
        return try Self.makePayload(updated)
    }

    public func deleteTask(taskID: String) async throws {
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

        guard networkDelayMode == .scenarioDriven else { return }

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

    private static func makePayload(_ dictionary: [String: Any]) throws -> DemoSyncPayload {
        do {
            return try DemoSyncPayload(dictionary: dictionary)
        } catch {
            throw DemoAPIError.invalidPayload(error.localizedDescription)
        }
    }
}
