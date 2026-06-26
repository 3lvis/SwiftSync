import DemoBackend
import Foundation

public typealias DemoSeedData = DemoBackend.DemoSeedData
public typealias DemoServerSimulator = DemoBackend.DemoServerSimulator

public enum DemoNetworkScenario: String, CaseIterable, Identifiable {
    case fastStable
    case slowNetwork
    case flakyNetwork

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fastStable: "Fast Stable"
        case .slowNetwork: "Slow Network"
        case .flakyNetwork: "Flaky Network"
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
            return "The device is offline."
        case .transient(let endpoint):
            return "Transient network failure while calling \(endpoint)."
        case .invalidPayload(let message):
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

    /// Simulated airplane mode at the transport: when on, every endpoint is unreachable (throws
    /// `.offline`), exactly like a device with no connectivity. This is where "offline" lives — the
    /// link between app and server — not in business logic. The sync engine reacts to it (reads keep
    /// serving the local cache, writes queue).
    public var isOffline = false

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
        return try Self.parseArray(backend.getProjectsPayload()).map(Self.makePayload)
    }

    public func getProjectTasks(projectID: String) async throws -> [DemoSyncPayload] {
        try await networkGate(endpoint: "GET /projects/{id}/tasks")
        return try Self.parseArray(backend.getProjectTasksPayload(projectID: projectID)).map(Self.makePayload)
    }

    public func getUsers() async throws -> [DemoSyncPayload] {
        try await networkGate(endpoint: "GET /users")
        return try Self.parseArray(backend.getUsersPayload()).map(Self.makePayload)
    }

    public func getTaskDetail(taskID: String) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "GET /tasks/{id}")
        guard let data = try backend.getTaskDetailPayload(publicID: taskID) else { return nil }
        return try Self.makePayload(Self.parseObject(data))
    }

    public func getTaskStateOptions() async throws -> [DemoSyncPayload] {
        try await networkGate(endpoint: "GET /task-state-options")
        return try Self.parseArray(backend.getTaskStateOptionsPayload()).map(Self.makePayload)
    }

    public func patchTaskState(taskID: String, state: String) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PATCH /tasks/{id} (state)")
        guard let data = try backend.patchTaskState(publicID: taskID, state: state) else { return nil }
        return try Self.makePayload(Self.parseObject(data))
    }

    public func patchTaskAssignee(taskID: String, assigneeID: String?) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PATCH /tasks/{id} (assignee_id)")
        guard let data = try backend.patchTaskAssignee(publicID: taskID, assigneeID: assigneeID) else { return nil }
        return try Self.makePayload(Self.parseObject(data))
    }

    public func replaceTaskReviewers(taskID: String, reviewerIDs: [String]) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PUT /tasks/{id}/reviewers")
        guard let data = try backend.replaceTaskReviewers(publicID: taskID, reviewerIDs: reviewerIDs) else {
            return nil
        }
        return try Self.makePayload(Self.parseObject(data))
    }

    public func replaceTaskWatchers(taskID: String, watcherIDs: [String]) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PUT /tasks/{id}/watchers")
        guard let data = try backend.replaceTaskWatchers(publicID: taskID, watcherIDs: watcherIDs) else {
            return nil
        }
        return try Self.makePayload(Self.parseObject(data))
    }

    public func createTask(body: DemoSyncPayload) async throws -> DemoSyncPayload {
        try await networkGate(endpoint: "POST /tasks")
        let created = try backend.createTask(body: Self.encodeData(body.toSyncPayloadDictionary()))
        return try Self.makePayload(Self.parseObject(created))
    }

    public func updateTask(taskID: String, body: DemoSyncPayload) async throws -> DemoSyncPayload? {
        try await networkGate(endpoint: "PUT /tasks/{id}")
        let updated = try backend.updateTask(publicID: taskID, body: Self.encodeData(body.toSyncPayloadDictionary()))
        return try Self.makePayload(Self.parseObject(updated))
    }

    public func deleteTask(taskID: String) async throws {
        try await networkGate(endpoint: "DELETE /tasks/{id}")
        try backend.deleteTask(publicID: taskID)
    }

    /// Test-only seam: awaited at the start of every `upload(operations:)`, before the network gate, so a
    /// test can deterministically park or observe each individual drain upload. `internal` so it never
    /// becomes part of the public surface — tests reach it via `@testable import`. Nil in production (inert).
    var beforeUpload: (@MainActor () async -> Void)?

    /// POST /sync/upload — the batched offline push. Returns the per-operation `results` array.
    public func upload(operations: [[String: Any]]) async throws -> [[String: Any]] {
        await beforeUpload?()
        try await networkGate(endpoint: "POST /sync/upload")
        let response = try Self.parseObject(backend.upload(operations: Self.encodeData(operations)))
        return (response["results"] as? [[String: Any]]) ?? []
    }

    private func networkGate(endpoint: String) async throws {
        if isOffline {
            throw DemoAPIError.offline
        }

        requestCounter += 1
        let callIndex = requestCounter

        switch scenario {
        case .flakyNetwork:
            if ((callIndex + endpoint.count) % 5) == 0 {
                throw DemoAPIError.transient(endpoint: endpoint)
            }
        case .fastStable, .slowNetwork:
            break
        }

        guard networkDelayMode == .scenarioDriven else { return }

        let baseDelayMS: UInt64 =
            switch scenario {
            case .fastStable: 150
            case .slowNetwork: 950
            case .flakyNetwork: 450
            }

        let isMutation =
            endpoint.hasPrefix("PATCH ") || endpoint.hasPrefix("POST ") || endpoint.hasPrefix("PUT ")
            || endpoint.hasPrefix("DELETE ")
        let mutationExtra: UInt64 =
            isMutation ? (scenario == .fastStable ? 220 : scenario == .flakyNetwork ? 120 : 0) : 0
        let hash = endpoint.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 10_000 }
        let jitter = UInt64((hash + callIndex * 17) % 250)
        try await _Concurrency.Task.sleep(nanoseconds: (baseDelayMS + jitter + mutationExtra) * 1_000_000)
    }

    /// Parses JSON response bytes from the backend — the client side of the wire (`JSONSerialization`
    /// preserves `null` as `NSNull` and raw value shapes, which is what inbound sync needs).
    private static func parseArray(_ data: Data) throws -> [[String: Any]] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DemoAPIError.invalidPayload("Expected a JSON array response")
        }
        return array
    }

    private static func parseObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DemoAPIError.invalidPayload("Expected a JSON object response")
        }
        return object
    }

    /// Encodes a request body to JSON bytes — the client side of the wire (what gets "sent").
    private static func encodeData(_ object: Any) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw DemoAPIError.invalidPayload("\(error)")
        }
    }

    private static func makePayload(_ dictionary: [String: Any]) throws -> DemoSyncPayload {
        do {
            return try DemoSyncPayload(dictionary: dictionary)
        } catch {
            throw DemoAPIError.invalidPayload(error.localizedDescription)
        }
    }
}
