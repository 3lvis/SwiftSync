import Combine
import Foundation
import SwiftData
import SwiftSync

@MainActor
final class ProjectsListMachine: ObservableObject {
    @Published private(set) var loadState: ScreenLoadState = .idle
    @Published private(set) var rows: [Project] = []

    private let syncEngine: DemoSyncEngine
    private let rowsPublisher: SyncQueryPublisher<Project>
    private let loadMachine: ScreenLoadMachine
    private var cancellables = Set<AnyCancellable>()

    init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.syncEngine = syncEngine
        self.rowsPublisher = SyncQueryPublisher(
            Project.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\Project.name), SortDescriptor(\Project.id)]
        )
        self.loadMachine = ScreenLoadMachine { error in
            presentError(error, retryActionTitle: "Retry", fallbackMessage: "Could not load projects.")
        }

        bind()
    }

    func send(_ event: ScreenLoadEvent) {
        loadMachine.send(event, run: { [syncEngine] in
            try await syncEngine.syncProjects()
        })
    }

    private func bind() {
        rowsPublisher.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                self?.rows = rows
            }
            .store(in: &cancellables)

        loadMachine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.loadState = state
            }
            .store(in: &cancellables)
    }
}

@MainActor
final class ProjectDetailMachine: ObservableObject {
    @Published private(set) var loadState: ScreenLoadState = .idle
    @Published private(set) var project: Project?
    @Published private(set) var tasks: [Task] = []

    private let projectID: String
    private let syncEngine: DemoSyncEngine
    private let projectPublisher: SyncQueryPublisher<Project>
    private let taskPublisher: SyncQueryPublisher<Task>
    private let loadMachine: ScreenLoadMachine
    private var cancellables = Set<AnyCancellable>()

    init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = projectID
        self.syncEngine = syncEngine
        self.projectPublisher = SyncQueryPublisher(
            Project.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\Project.name), SortDescriptor(\Project.id)]
        )
        self.taskPublisher = SyncQueryPublisher(
            Task.self,
            relationship: \Task.project,
            relationshipID: projectID,
            in: syncContainer,
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.id)
            ]
        )
        self.loadMachine = ScreenLoadMachine { error in
            presentError(error, retryActionTitle: "Retry", fallbackMessage: "Could not load this project yet.")
        }

        bind()
    }

    func send(_ event: ScreenLoadEvent) {
        loadMachine.send(event, run: { [syncEngine, projectID] in
            try await syncEngine.syncProjectTasks(projectID: projectID)
        })
    }

    func deleteTask(taskID: String) async {
        do {
            try await syncEngine.deleteTask(taskID: taskID, projectID: projectID)
        } catch {
            // Screen-level load state handles sync failures and retry affordances.
        }
    }

    private func bind() {
        projectPublisher.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                guard let self else { return }
                self.project = rows.first(where: { $0.id == self.projectID })
            }
            .store(in: &cancellables)

        taskPublisher.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                self?.tasks = rows
            }
            .store(in: &cancellables)

        loadMachine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.loadState = state
            }
            .store(in: &cancellables)
    }
}

@MainActor
final class TaskDetailMachine: ObservableObject {
    @Published private(set) var loadState: ScreenLoadState = .idle
    @Published private(set) var task: Task?
    @Published private(set) var items: [Item] = []

    private let taskID: String
    private let syncEngine: DemoSyncEngine
    private let taskPublisher: SyncQueryPublisher<Task>
    private let itemPublisher: SyncQueryPublisher<Item>
    private let loadMachine: ScreenLoadMachine
    private var cancellables = Set<AnyCancellable>()

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncEngine = syncEngine
        self.taskPublisher = SyncQueryPublisher(
            Task.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\Task.updatedAt, order: .reverse), SortDescriptor(\Task.id)]
        )
        self.itemPublisher = SyncQueryPublisher(
            Item.self,
            relationship: \Item.task,
            relationshipID: taskID,
            in: syncContainer,
            sortBy: [SortDescriptor(\Item.position, order: .forward), SortDescriptor(\Item.id, order: .forward)]
        )
        self.loadMachine = ScreenLoadMachine { error in
            presentError(error, retryActionTitle: "Retry", fallbackMessage: "Could not load this task yet.")
        }

        bind()
    }

    func send(_ event: ScreenLoadEvent) {
        loadMachine.send(event, run: { [syncEngine, taskID] in
            try await syncEngine.syncTaskDetail(taskID: taskID)
        })
    }

    private func bind() {
        taskPublisher.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                guard let self else { return }
                self.task = rows.first(where: { $0.id == self.taskID })
            }
            .store(in: &cancellables)

        itemPublisher.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                self?.items = rows
            }
            .store(in: &cancellables)

        loadMachine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.loadState = state
            }
            .store(in: &cancellables)
    }
}

@MainActor
final class TaskFormMachine: ObservableObject {
    @Published private(set) var users: [User] = []
    @Published private(set) var taskStateOptions: [TaskStateOption] = []
    @Published private(set) var metadataLoadState: ScreenLoadState = .idle
    @Published private(set) var saveState: SubmissionState = .idle

    private let syncContainer: SyncContainer
    private let syncEngine: DemoSyncEngine
    private let editContext: ModelContext
    private let metadataLoadMachine: ScreenLoadMachine
    private let saveMachine: SubmissionMachine
    private var cancellables = Set<AnyCancellable>()

    init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine, editContext: ModelContext) {
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        self.editContext = editContext
        self.metadataLoadMachine = ScreenLoadMachine { error in
            presentError(
                error,
                retryActionTitle: "Retry Loading Metadata",
                fallbackMessage: "Could not load form options yet."
            )
        }
        self.saveMachine = SubmissionMachine { error in
            presentError(
                error,
                retryActionTitle: nil,
                fallbackMessage: "Could not save this task."
            )
        }

        bind()
    }

    func sendMetadata(_ event: ScreenLoadEvent) {
        metadataLoadMachine.send(event, run: { [syncEngine] in
            try await syncEngine.syncTaskFormMetadata()
            await MainActor.run {
                self.refreshMetadataSnapshot()
            }
        })
    }

    func prepareMetadata() {
        refreshMetadataSnapshot()
    }

    func dismissSaveError() {
        _ = saveMachine.send(.dismissError)
    }

    func prepareDraftForSave(_ draft: Task, normalizeItems: () -> Void) {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.descriptionText = "No description yet."
        }
        normalizeItems()
        draft.updatedAt = Date()
    }

    func applyDefaultStateIfNeeded(to draft: Task) {
        guard !taskStateOptions.isEmpty,
              draft.state.isEmpty || !taskStateOptions.contains(where: { $0.id == draft.state }),
              let first = taskStateOptions.first
        else { return }

        draft.state = first.id
        draft.stateLabel = first.label
    }

    func applyDefaultAuthorIfNeeded(to draft: Task) {
        guard !users.isEmpty,
              draft.authorID.isEmpty || !users.contains(where: { $0.id == draft.authorID })
        else { return }

        draft.authorID = draft.assigneeID.flatMap { id in
            users.contains(where: { $0.id == id }) ? id : nil
        } ?? users.first?.id ?? ""
    }

    func save(
        mode: TaskFormMode,
        draft: Task,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        guard saveMachine.send(.submit) else { return }

        let body = draft.exportObject(for: syncContainer)
        let capturedReviewerIDs = draft.reviewers.map(\.id).sorted()
        let capturedWatcherIDs = draft.watchers.map(\.id).sorted()

        var reviewersChanged = false
        var watchersChanged = false
        if case .edit(let originalTask) = mode {
            let originalReviewerIDs = Set(originalTask.reviewers.map(\.id))
            let originalWatcherIDs = Set(originalTask.watchers.map(\.id))
            reviewersChanged = Set(capturedReviewerIDs) != originalReviewerIDs
            watchersChanged = Set(capturedWatcherIDs) != originalWatcherIDs
        }

        _Concurrency.Task {
            do {
                switch mode {
                case .create(let projectID):
                    try await syncEngine.createTask(body: body, projectID: projectID)
                    if !capturedReviewerIDs.isEmpty {
                        try await syncEngine.replaceTaskReviewers(
                            taskID: draft.id,
                            projectID: projectID,
                            reviewerIDs: capturedReviewerIDs
                        )
                    }
                    if !capturedWatcherIDs.isEmpty {
                        try await syncEngine.replaceTaskWatchers(
                            taskID: draft.id,
                            projectID: projectID,
                            watcherIDs: capturedWatcherIDs
                        )
                    }

                case .edit(let task):
                    try await syncEngine.updateTask(taskID: task.id, projectID: task.projectID, body: body)
                    if reviewersChanged {
                        try await syncEngine.replaceTaskReviewers(
                            taskID: task.id,
                            projectID: task.projectID,
                            reviewerIDs: capturedReviewerIDs
                        )
                    }
                    if watchersChanged {
                        try await syncEngine.replaceTaskWatchers(
                            taskID: task.id,
                            projectID: task.projectID,
                            watcherIDs: capturedWatcherIDs
                        )
                    }
                }
                await MainActor.run {
                    _ = saveMachine.send(.success)
                    onSuccess()
                }
            } catch {
                await MainActor.run {
                    _ = saveMachine.send(.failure(error))
                }
            }
        }
    }

    private func bind() {
        metadataLoadMachine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.metadataLoadState = state
            }
            .store(in: &cancellables)

        saveMachine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.saveState = state
            }
            .store(in: &cancellables)
    }

    private func refreshMetadataSnapshot() {
        let snapshot = Self.metadataSnapshot(from: editContext)
        users = snapshot.users
        taskStateOptions = snapshot.taskStateOptions
    }

    private static func metadataSnapshot(from context: ModelContext) -> (users: [User], taskStateOptions: [TaskStateOption]) {
        let userDescriptor = FetchDescriptor<User>(
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)]
        )
        let users = (try? context.fetch(userDescriptor)) ?? []

        let stateDescriptor = FetchDescriptor<TaskStateOption>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)]
        )
        let taskStateOptions = (try? context.fetch(stateDescriptor)) ?? []

        return (users, taskStateOptions)
    }
}
