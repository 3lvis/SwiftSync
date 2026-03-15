import XCTest
import SwiftData
import SwiftSync
import Observation

@Syncable
@Model
final class ModelPubTask {
    @Attribute(.unique) var id: String
    var title: String
    var assigneeID: String?
    var assignee: ModelPubUser?

    init(id: String, title: String, assigneeID: String? = nil, assignee: ModelPubUser? = nil) {
        self.id = id
        self.title = title
        self.assigneeID = assigneeID
        self.assignee = assignee
    }
}

@Syncable
@Model
final class ModelPubUser {
    @Attribute(.unique) var id: String
    var displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

final class SyncModelPublisherTests: XCTestCase {

    @MainActor
    func testPublisherEventuallyEmitsAssignedAndHydratedRowAfterBackgroundSync() async throws {
        let syncContainer = try makeContainer(modelTypes: ModelPubTask.self, ModelPubUser.self)

        try await syncContainer.sync(
            payload: [["id": "u1", "display_name": "Alice", "role": ["id": "eng", "label": "Engineer"]]],
            as: ModelPubUser.self
        )
        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Alpha", "assignee_id": NSNull()]],
            as: ModelPubTask.self
        )

        let publisher = SyncModelPublisher(ModelPubTask.self, id: "t1", in: syncContainer)
        let spy = ObservationSpy<(String?, String?)> {
            (publisher.row?.assigneeID, publisher.row?.assignee?.id)
        }
        let initialRow = try XCTUnwrap(publisher.row)

        XCTAssertEqual(spy.values.last?.0 ?? nil, nil)
        XCTAssertEqual(spy.values.last?.1 ?? nil, nil)

        try await syncContainer.sync(
            item: ["id": "t1", "title": "Alpha", "assignee_id": "u1"],
            as: ModelPubTask.self
        )

        try await waitUntil {
            publisher.row?.assigneeID == "u1" && publisher.row?.assignee?.id == "u1"
        }

        let finalRow = try XCTUnwrap(publisher.row)
        XCTAssertTrue(initialRow === finalRow)
        XCTAssertEqual(publisher.row?.assigneeID, "u1")
        XCTAssertEqual(publisher.row?.assignee?.id, "u1")
        XCTAssertTrue(
            spy.values.contains(where: { $0.0 == "u1" && $0.1 == "u1" }),
            "spy values: \(spy.values)"
        )
    }

    @MainActor
    func testPublisherSpyRecordsTransitionFromNilToAssigned() async throws {
        let syncContainer = try makeContainer(modelTypes: ModelPubTask.self, ModelPubUser.self)

        try await syncContainer.sync(
            payload: [["id": "u1", "display_name": "Alice", "role": ["id": "eng", "label": "Engineer"]]],
            as: ModelPubUser.self
        )
        try await syncContainer.sync(
            payload: [["id": "t1", "title": "Alpha", "assignee_id": NSNull()]],
            as: ModelPubTask.self
        )

        let publisher = SyncModelPublisher(ModelPubTask.self, id: "t1", in: syncContainer)
        let spy = ObservationSpy<(String?, String?)> {
            (publisher.row?.assigneeID, publisher.row?.assignee?.id)
        }
        let initialRow = try XCTUnwrap(publisher.row)

        try await syncContainer.sync(
            item: ["id": "t1", "title": "Alpha", "assignee_id": "u1"],
            as: ModelPubTask.self
        )

        try await waitUntil {
            spy.values.contains(where: { $0.0 == "u1" })
        }

        let finalRow = try XCTUnwrap(publisher.row)
        XCTAssertTrue(initialRow === finalRow)
        XCTAssertEqual(publisher.row?.assigneeID, "u1")
        XCTAssertEqual(publisher.row?.assignee?.id, "u1")
        XCTAssertEqual(spy.values.first?.0 ?? nil, nil)
        XCTAssertEqual(spy.values.first?.1 ?? nil, nil)
        XCTAssertTrue(
            spy.values.contains(where: { $0.0 == "u1" }),
            "spy values: \(spy.values)"
        )
    }

    @MainActor
    func testPublisherSpyRecordsToManyMembershipChangeForSameRowIdentity() async throws {
        let syncContainer = try makeContainer(modelTypes: OneSidedTask.self, OneSidedUser.self)

        try await syncContainer.sync(
            payload: [
                ["id": 1, "name": "Alice"],
                ["id": 2, "name": "Bob"],
                ["id": 3, "name": "Cara"]
            ],
            as: OneSidedUser.self
        )
        try await syncContainer.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [1, 2]]],
            as: OneSidedTask.self
        )

        let publisher = SyncModelPublisher(OneSidedTask.self, id: 10, in: syncContainer)
        let initialRow = try XCTUnwrap(publisher.row)
        let spy = ObservationSpy<[Int]> {
            publisher.row?.members.map(\.id).sorted() ?? []
        }

        XCTAssertEqual(spy.values.first, [1, 2])

        try await syncContainer.sync(
            payload: [["id": 10, "title": "Task 10", "member_ids": [2, 3]]],
            as: OneSidedTask.self
        )

        try await waitUntil {
            publisher.row?.members.map(\.id).sorted() == [2, 3]
        }

        let finalRow = try XCTUnwrap(publisher.row)
        XCTAssertTrue(initialRow === finalRow)
        XCTAssertEqual(finalRow.members.map(\.id).sorted(), [2, 3])
        XCTAssertTrue(
            spy.values.contains(where: { $0 == [2, 3] }),
            "spy values: \(spy.values)"
        )
    }

    @MainActor
    private func makeContainer(modelTypes: any PersistentModel.Type...) throws -> SyncContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: Schema(modelTypes), configurations: config)
        return SyncContainer(modelContainer)
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await _Concurrency.Task.sleep(nanoseconds: pollNanoseconds)
        }
        XCTFail("Condition not satisfied before timeout")
    }
}

@MainActor
private final class ObservationSpy<Value> {
    private let read: @MainActor () -> Value
    private(set) var values: [Value] = []

    init(read: @escaping @MainActor () -> Value) {
        self.read = read
        observe()
    }

    private func observe() {
        withObservationTracking {
            values.append(read())
        } onChange: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.observe()
            }
        }
    }
}
