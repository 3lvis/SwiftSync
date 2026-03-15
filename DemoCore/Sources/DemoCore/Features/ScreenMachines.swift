import Foundation
import Observation
import SwiftData
@preconcurrency import SwiftSync

public enum TaskFormMode {
    case create(projectID: String)
    case edit(task: Task)
}

public enum ProjectsListStatusState: Equatable {
    case hidden
    case loading
    case empty
    case error(ErrorPresentationState)
}

public enum ProjectDetailContentState: Equatable {
    case loading
    case content
    case notFound
}

public enum TaskDetailContentState: Equatable {
    case loading
    case content
    case notFound
}

public enum TaskFormOptionsState: Equatable {
    case loading
    case available
    case unavailable
}

func resolveProjectsListStatusState(loadState: ScreenLoadState, hasRows: Bool) -> ProjectsListStatusState {
    switch loadState {
    case .idle:
        return .hidden
    case .loading:
        return hasRows ? .hidden : .loading
    case .loaded:
        return hasRows ? .hidden : .empty
    case .error(let presentation):
        return .error(presentation)
    }
}

func resolveProjectDetailContentState(
    loadState: ScreenLoadState,
    hasProject: Bool,
    hasTasks: Bool
) -> ProjectDetailContentState {
    if hasProject || hasTasks {
        return .content
    }
    return loadState.isLoading ? .loading : .notFound
}

func resolveTaskDetailContentState(loadState: ScreenLoadState, hasTask: Bool) -> TaskDetailContentState {
    if hasTask {
        return .content
    }
    return loadState.isLoading ? .loading : .notFound
}

func resolveTaskFormOptionsState(loadState: ScreenLoadState, hasOptions: Bool) -> TaskFormOptionsState {
    if hasOptions {
        return .available
    }
    return loadState.isLoading ? .loading : .unavailable
}

@MainActor
@Observable
public final class ProjectsViewMachine {
    public private(set) var loadState: ScreenLoadState = .idle
    public var rows: [Project] {
        rowsPublisher.rows
    }
    public var statusState: ProjectsListStatusState {
        resolveProjectsListStatusState(loadState: loadState, hasRows: !rows.isEmpty)
    }

    private let syncEngine: DemoSyncEngine
    private let rowsPublisher: SyncQueryPublisher<Project>
    private let loadMachine: ScreenLoadMachine
    public init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.syncEngine = syncEngine
        self.rowsPublisher = SyncQueryPublisher(
            Project.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\Project.name), SortDescriptor(\Project.id)]
        )
        self.loadMachine = ScreenLoadMachine { error in
            presentError(error, fallbackMessage: "Could not load projects.")
        }

        observeContinuously {
            self.loadState = self.loadMachine.state
        }
    }

    public func send(_ event: ScreenLoadEvent) {
        loadMachine.send(event, run: { [syncEngine] in
            try await syncEngine.syncProjects()
        })
    }

}

@MainActor
@Observable
public final class ProjectViewMachine {
    public private(set) var loadState: ScreenLoadState = .idle
    public private(set) var deleteState: SubmissionState = .idle
    public var project: Project? {
        projectPublisher.rows.first(where: { $0.id == projectID })
    }
    public var tasks: [Task] {
        taskPublisher.rows
    }
    public var contentState: ProjectDetailContentState {
        resolveProjectDetailContentState(
            loadState: loadState,
            hasProject: project != nil,
            hasTasks: !tasks.isEmpty
        )
    }
    public var loadErrorPresentation: ErrorPresentationState? {
        loadState.errorPresentation
    }

    private let projectID: String
    private let syncEngine: DemoSyncEngine
    private let projectPublisher: SyncQueryPublisher<Project>
    private let taskPublisher: SyncQueryPublisher<Task>
    private let loadMachine: ScreenLoadMachine
    private let deleteMachine: SubmissionMachine
    public enum DeleteEvent {
        case request(taskID: String)
        case dismissError
    }

    public init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
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
            presentError(error, fallbackMessage: "Could not load this project yet.")
        }
        self.deleteMachine = SubmissionMachine { error in
            presentError(error, fallbackMessage: "Could not delete this task.")
        }

        observeContinuously {
            self.loadState = self.loadMachine.state
        }
        observeContinuously {
            self.deleteState = self.deleteMachine.state
        }
    }

    public func send(_ event: ScreenLoadEvent) {
        loadMachine.send(event, run: { [syncEngine, projectID] in
            try await syncEngine.syncProjectTasks(projectID: projectID)
        })
    }

    public func sendDelete(_ event: DeleteEvent) {
        switch event {
        case .request(let taskID):
            guard deleteMachine.send(.submit) else { return }

            _Concurrency.Task {
                do {
                    try await syncEngine.deleteTask(taskID: taskID, projectID: projectID)
                    await MainActor.run {
                        _ = deleteMachine.send(.success)
                    }
                } catch {
                    await MainActor.run {
                        _ = deleteMachine.send(.failure(error))
                    }
                }
            }

        case .dismissError:
            _ = deleteMachine.send(.dismissError)
        }
    }

}

@MainActor
@Observable
public final class TaskViewMachine {
    public private(set) var loadState: ScreenLoadState = .idle
    public var task: Task? {
        taskPublisher.row
    }
    public var items: [Item] {
        itemPublisher.rows
    }
    public var reviewerNames: [String] {
        guard let task else { return [] }
        return task.reviewers.map(\.displayName).sorted()
    }
    public var watcherNames: [String] {
        guard let task else { return [] }
        return task.watchers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map(\.displayName)
    }
    public var contentState: TaskDetailContentState {
        resolveTaskDetailContentState(loadState: loadState, hasTask: task != nil)
    }
    public var loadErrorPresentation: ErrorPresentationState? {
        loadState.errorPresentation
    }

    private let taskID: String
    private let syncEngine: DemoSyncEngine
    private let taskPublisher: SyncModelPublisher<Task>
    private let itemPublisher: SyncQueryPublisher<Item>
    private let loadMachine: ScreenLoadMachine
    public init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncEngine = syncEngine
        self.taskPublisher = SyncModelPublisher(
            Task.self,
            id: taskID,
            in: syncContainer,
        )
        self.itemPublisher = SyncQueryPublisher(
            Item.self,
            relationship: \Item.task,
            relationshipID: taskID,
            in: syncContainer,
            sortBy: [SortDescriptor(\Item.position, order: .forward), SortDescriptor(\Item.id, order: .forward)]
        )
        self.loadMachine = ScreenLoadMachine { error in
            presentError(error, fallbackMessage: "Could not load this task yet.")
        }

        observeContinuously {
            self.loadState = self.loadMachine.state
        }
    }

    public func send(_ event: ScreenLoadEvent) {
        loadMachine.send(event, run: { [syncEngine, taskID] in
            try await syncEngine.syncTaskDetail(taskID: taskID)
        })
    }
}

@MainActor
@Observable
public final class TaskFormSheetMachine {
    public private(set) var users: [User] = []
    public private(set) var taskStateOptions: [TaskStateOption] = []
    public private(set) var metadataLoadState: ScreenLoadState = .idle
    public private(set) var saveState: SubmissionState = .idle
    public var taskStateOptionsState: TaskFormOptionsState {
        resolveTaskFormOptionsState(loadState: metadataLoadState, hasOptions: !taskStateOptions.isEmpty)
    }
    public var userOptionsState: TaskFormOptionsState {
        resolveTaskFormOptionsState(loadState: metadataLoadState, hasOptions: !users.isEmpty)
    }
    public var metadataErrorPresentation: ErrorPresentationState? {
        metadataLoadState.errorPresentation
    }

    private let syncContainer: SyncContainer
    private let syncEngine: DemoSyncEngine
    private let editContext: ModelContext
    private let metadataLoadMachine: ScreenLoadMachine
    private let saveMachine: SubmissionMachine
    public enum ItemMutation {
        case add(title: String)
        case updateTitle(item: Item, title: String)
        case delete(Item)
        case move(from: IndexSet, to: Int)
    }

    public enum Event {
        case metadata(ScreenLoadEvent)
        case save(mode: TaskFormMode, draft: Task, onSuccess: @MainActor () -> Void)
        case dismissSaveError
    }

    public init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine, editContext: ModelContext) {
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        self.editContext = editContext
        self.metadataLoadMachine = ScreenLoadMachine { error in
            presentError(
                error,
                fallbackMessage: "Could not load form options yet."
            )
        }
        self.saveMachine = SubmissionMachine { error in
            presentError(
                error,
                fallbackMessage: "Could not save this task."
            )
        }

        observeContinuously {
            self.metadataLoadState = self.metadataLoadMachine.state
        }
        observeContinuously {
            self.saveState = self.saveMachine.state
        }
    }

    public func send(_ event: Event) {
        switch event {
        case .metadata(let loadEvent):
            if case .onAppear = loadEvent {
                refreshMetadataSnapshot()
            }

            metadataLoadMachine.send(loadEvent, run: { [syncEngine] in
                try await syncEngine.syncTaskFormMetadata()
                await MainActor.run {
                    self.refreshMetadataSnapshot()
                }
            })

        case .save(let mode, let draft, let onSuccess):
            applyDefaultsIfNeeded(to: draft)
            draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.descriptionText = draft.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.descriptionText?.isEmpty == true {
                draft.descriptionText = nil
            }
            normalizeItemPositions(in: draft)
            draft.updatedAt = Date()

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
                        let createPayload = try DemoSyncPayload(dictionary: body)
                        try await syncEngine.createTask(body: createPayload, projectID: projectID)
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
                        let updatePayload = try DemoSyncPayload(dictionary: body)
                        try await syncEngine.updateTask(taskID: task.id, projectID: task.projectID, body: updatePayload)
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

        case .dismissSaveError:
            _ = saveMachine.send(.dismissError)
        }
    }

    public func sortedItems(in draft: Task) -> [Item] {
        draft.items.sorted {
            if $0.position == $1.position {
                return $0.id < $1.id
            }
            return $0.position < $1.position
        }
    }

    @discardableResult
    public func mutateItems(_ mutation: ItemMutation, in draft: Task) -> Bool {
        switch mutation {
        case .add(let title):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }

            let item = Item(
                taskID: draft.id,
                title: trimmed,
                position: draft.items.count,
                createdAt: Date(),
                updatedAt: Date(),
                task: draft
            )
            draft.items.append(item)
            normalizeItemPositions(in: draft)
            return true

        case .updateTitle(let item, let title):
            item.title = title
            item.updatedAt = Date()
            return true

        case .delete(let item):
            draft.items.removeAll { $0.id == item.id }
            editContext.delete(item)
            normalizeItemPositions(in: draft)
            return true

        case .move(let source, let destination):
            var reordered = sortedItems(in: draft)
            reordered = reorderItems(reordered, from: source, to: destination)
            for (index, item) in reordered.enumerated() {
                item.position = index
                item.updatedAt = Date()
            }
            return true
        }
    }

    public func normalizeItemPositions(in draft: Task) {
        for (index, item) in sortedItems(in: draft).enumerated() {
            item.position = index
        }
    }

    public func applyDefaultsIfNeeded(to draft: Task) {
        if !taskStateOptions.isEmpty,
           (draft.state.isEmpty || !taskStateOptions.contains(where: { $0.id == draft.state })),
           let first = taskStateOptions.first {
            draft.state = first.id
            draft.stateLabel = first.label
        }

        if !users.isEmpty,
           (draft.authorID.isEmpty || !users.contains(where: { $0.id == draft.authorID })) {
            draft.authorID = draft.assigneeID.flatMap { id in
                users.contains(where: { $0.id == id }) ? id : nil
            } ?? users.first?.id ?? ""
        }
    }

    private func refreshMetadataSnapshot() {
        let userDescriptor = FetchDescriptor<User>(
            sortBy: [SortDescriptor(\.displayName), SortDescriptor(\.id)]
        )
        users = (try? editContext.fetch(userDescriptor)) ?? []

        let stateDescriptor = FetchDescriptor<TaskStateOption>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.id)]
        )
        taskStateOptions = (try? editContext.fetch(stateDescriptor)) ?? []
    }

    private func reorderItems(_ items: [Item], from source: IndexSet, to destination: Int) -> [Item] {
        guard !items.isEmpty else { return items }

        var reordered = items
        let validSource = source.filter { reordered.indices.contains($0) }
        guard !validSource.isEmpty else { return reordered }

        let moving = validSource.map { reordered[$0] }
        for index in validSource.sorted(by: >) {
            reordered.remove(at: index)
        }

        let removedBeforeDestination = validSource.filter { $0 < destination }.count
        let adjustedDestination = max(0, min(reordered.count, destination - removedBeforeDestination))
        reordered.insert(contentsOf: moving, at: adjustedDestination)
        return reordered
    }

}
