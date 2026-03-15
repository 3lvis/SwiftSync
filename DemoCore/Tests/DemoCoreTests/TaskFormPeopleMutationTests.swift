import SwiftData
import SwiftSync
import XCTest
import Observation
@testable import DemoCore

final class TaskFormPeopleMutationTests: XCTestCase {

    @MainActor
    func testEditTaskPeopleFlowReplacesReviewersAndWatchers() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.notificationsReliability
        let taskID = DemoSeedData.SeedIDs.Tasks.duplicatePushFix

        try await engine.syncProjectTasks(projectID: projectID)
        try await engine.syncTaskDetail(taskID: taskID)
        try await engine.syncTaskFormMetadata()

        let originalTask = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(originalTask.reviewers.map(\.id).sorted(), [DemoSeedData.SeedIDs.Users.noahKim])
        XCTAssertEqual(
            originalTask.watchers.map(\.id).sorted(),
            [DemoSeedData.SeedIDs.Users.ethanLee, DemoSeedData.SeedIDs.Users.liamBrown].sorted()
        )

        let editContext = ModelContext(syncContainer.modelContainer)
        editContext.autosaveEnabled = false
        let machine = TaskFormSheetMachine(syncContainer: syncContainer, syncEngine: engine, editContext: editContext)
        machine.send(.metadata(.onAppear))
        try await waitUntil {
            machine.userOptionsState == .available && machine.taskStateOptionsState == .available
        }

        let draft = try XCTUnwrap(fetchTask(id: taskID, in: editContext))

        // Match the UI flow:
        // assignee -> Mia
        // reviewer Noah off
        // reviewer Sofia on
        // watcher Ethan off
        // watcher Sofia on
        draft.assigneeID = DemoSeedData.SeedIDs.Users.miaPatel
        draft.reviewers.removeAll(where: { $0.id == DemoSeedData.SeedIDs.Users.noahKim })
        if !draft.reviewers.contains(where: { $0.id == DemoSeedData.SeedIDs.Users.sofiaGarcia }) {
            let sofia = try XCTUnwrap(fetchUser(id: DemoSeedData.SeedIDs.Users.sofiaGarcia, in: editContext))
            draft.reviewers.append(sofia)
        }
        draft.watchers.removeAll(where: { $0.id == DemoSeedData.SeedIDs.Users.ethanLee })
        if !draft.watchers.contains(where: { $0.id == DemoSeedData.SeedIDs.Users.sofiaGarcia }) {
            let sofia = try XCTUnwrap(fetchUser(id: DemoSeedData.SeedIDs.Users.sofiaGarcia, in: editContext))
            draft.watchers.append(sofia)
        }

        let saved = expectation(description: "save callback")
        machine.send(.save(mode: .edit(task: originalTask), draft: draft, onSuccess: {
            saved.fulfill()
        }))
        await fulfillment(of: [saved], timeout: 10)

        let updatedTask = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        XCTAssertEqual(updatedTask.assigneeID, DemoSeedData.SeedIDs.Users.miaPatel)
        XCTAssertEqual(updatedTask.reviewers.map(\.id).sorted(), [DemoSeedData.SeedIDs.Users.sofiaGarcia])
        XCTAssertEqual(
            updatedTask.watchers.map(\.id).sorted(),
            [DemoSeedData.SeedIDs.Users.liamBrown, DemoSeedData.SeedIDs.Users.sofiaGarcia].sorted()
        )
    }

    @MainActor
    func testTaskViewMachineObservesReviewerAndWatcherChangesAfterPeopleSave() async throws {
        let seed = DemoSeedData.generate()
        let syncContainer = try makeSyncContainer()
        let apiClient = FakeDemoAPIClient(seedData: seed)
        let engine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)

        let projectID = DemoSeedData.SeedIDs.Projects.notificationsReliability
        let taskID = DemoSeedData.SeedIDs.Tasks.duplicatePushFix

        try await engine.syncProjectTasks(projectID: projectID)
        try await engine.syncTaskDetail(taskID: taskID)
        try await engine.syncTaskFormMetadata()

        let detailMachine = TaskViewMachine(taskID: taskID, syncContainer: syncContainer, syncEngine: engine)
        detailMachine.send(.onAppear)
        try await waitUntil {
            detailMachine.task?.id == taskID
                && detailMachine.task?.reviewers.map(\.id).sorted() == [DemoSeedData.SeedIDs.Users.noahKim]
                && detailMachine.task?.watchers.map(\.id).sorted()
                    == [DemoSeedData.SeedIDs.Users.ethanLee, DemoSeedData.SeedIDs.Users.liamBrown].sorted()
        }

        let spy = ObservationSpy {
            (
                detailMachine.task?.assignee?.displayName,
                detailMachine.task?.reviewers.map(\.id).sorted() ?? [],
                detailMachine.task?.watchers.map(\.id).sorted() ?? []
            )
        }

        let originalTask = try XCTUnwrap(fetchTask(id: taskID, in: syncContainer.mainContext))
        let editContext = ModelContext(syncContainer.modelContainer)
        editContext.autosaveEnabled = false
        let formMachine = TaskFormSheetMachine(syncContainer: syncContainer, syncEngine: engine, editContext: editContext)
        formMachine.send(.metadata(.onAppear))
        try await waitUntil {
            formMachine.userOptionsState == .available && formMachine.taskStateOptionsState == .available
        }

        let draft = try XCTUnwrap(fetchTask(id: taskID, in: editContext))
        draft.assigneeID = DemoSeedData.SeedIDs.Users.miaPatel
        draft.reviewers.removeAll(where: { $0.id == DemoSeedData.SeedIDs.Users.noahKim })
        if !draft.reviewers.contains(where: { $0.id == DemoSeedData.SeedIDs.Users.sofiaGarcia }) {
            let sofia = try XCTUnwrap(fetchUser(id: DemoSeedData.SeedIDs.Users.sofiaGarcia, in: editContext))
            draft.reviewers.append(sofia)
        }
        draft.watchers.removeAll(where: { $0.id == DemoSeedData.SeedIDs.Users.ethanLee })
        if !draft.watchers.contains(where: { $0.id == DemoSeedData.SeedIDs.Users.sofiaGarcia }) {
            let sofia = try XCTUnwrap(fetchUser(id: DemoSeedData.SeedIDs.Users.sofiaGarcia, in: editContext))
            draft.watchers.append(sofia)
        }

        let saved = expectation(description: "save callback")
        formMachine.send(.save(mode: .edit(task: originalTask), draft: draft, onSuccess: {
            saved.fulfill()
        }))
        await fulfillment(of: [saved], timeout: 10)

        try await waitUntil {
            detailMachine.task?.assignee?.displayName == "Mia Patel"
                && detailMachine.task?.reviewers.map(\.id).sorted() == [DemoSeedData.SeedIDs.Users.sofiaGarcia]
                && detailMachine.task?.watchers.map(\.id).sorted()
                    == [DemoSeedData.SeedIDs.Users.liamBrown, DemoSeedData.SeedIDs.Users.sofiaGarcia].sorted()
        }

        XCTAssertTrue(
            spy.values.contains(where: {
                $0.0 == "Mia Patel"
                    && $0.1 == [DemoSeedData.SeedIDs.Users.sofiaGarcia]
                    && $0.2 == [DemoSeedData.SeedIDs.Users.liamBrown, DemoSeedData.SeedIDs.Users.sofiaGarcia].sorted()
            }),
            "spy values: \(spy.values)"
        )
    }

    @MainActor
    private func makeSyncContainer() throws -> SyncContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try SyncContainer(
            for: Project.self,
            User.self,
            Task.self,
            Item.self,
            TaskStateOption.self,
            configurations: configuration
        )
    }

    @MainActor
    private func fetchTask(id: String, in context: ModelContext) throws -> Task? {
        try context.fetch(FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })).first
    }

    @MainActor
    private func fetchUser(id: String, in context: ModelContext) throws -> User? {
        try context.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.id == id })).first
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
