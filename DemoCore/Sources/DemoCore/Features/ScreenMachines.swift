import Foundation
import Observation
import SwiftData
@preconcurrency import SwiftSync

public enum TaskFormMode {
    case create(projectID: String)
    case edit(task: Task)
}

@MainActor
@Observable
public final class ProjectsListMachine {
    public private(set) var loadState: ScreenLoadState = .idle
    public private(set) var rows: [Project] = []

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
            self.rows = self.rowsPublisher.rows
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
public final class ProjectDetailMachine {
    public private(set) var loadState: ScreenLoadState = .idle
    public private(set) var deleteState: SubmissionState = .idle
    public private(set) var project: Project?
    public private(set) var tasks: [Task] = []

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
            self.project = self.projectPublisher.rows.first(where: { $0.id == self.projectID })
            DemoDebugLog.emit(
                "projectDetail.publisher.project",
                "projectID=\(self.projectID) project=\(self.project?.id ?? "nil") taskCount=\(self.project?.taskCount ?? -1)"
            )
        }
        observeContinuously {
            self.tasks = self.taskPublisher.rows
            DemoDebugLog.emit(
                "projectDetail.publisher.tasks",
                "projectID=\(self.projectID) tasks=\(self.tasks.map(\.id).sorted())"
            )
        }
        observeContinuously {
            self.loadState = self.loadMachine.state
            DemoDebugLog.emit(
                "projectDetail.loadState",
                "projectID=\(self.projectID) state=\(self.debugLoadState(self.loadState))"
            )
        }
        observeContinuously {
            self.deleteState = self.deleteMachine.state
        }
    }

    public func send(_ event: ScreenLoadEvent) {
        DemoDebugLog.emit("projectDetail.event", "projectID=\(projectID) event=\(String(describing: event))")
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

    private func debugLoadState(_ state: ScreenLoadState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .error(let presentation):
            return "error(\(presentation.message))"
        }
    }

}

@MainActor
@Observable
public final class TaskDetailMachine {
    public private(set) var loadState: ScreenLoadState = .idle
    public private(set) var task: Task?
    public private(set) var items: [Item] = []

    private let taskID: String
    private let syncEngine: DemoSyncEngine
    private let taskPublisher: SyncQueryPublisher<Task>
    private let itemPublisher: SyncQueryPublisher<Item>
    private let loadMachine: ScreenLoadMachine
    public init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
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
            presentError(error, fallbackMessage: "Could not load this task yet.")
        }

        observeContinuously {
            self.task = self.taskPublisher.rows.first(where: { $0.id == self.taskID })
            DemoDebugLog.emit(
                "taskDetail.publisher.task",
                self.debugTaskSnapshot(self.task)
            )
        }
        observeContinuously {
            self.items = self.itemPublisher.rows
            DemoDebugLog.emit(
                "taskDetail.publisher.items",
                "taskID=\(self.taskID) items=\(self.items.map(\.id).sorted())"
            )
        }
        observeContinuously {
            self.loadState = self.loadMachine.state
        }
    }

    public func send(_ event: ScreenLoadEvent) {
        DemoDebugLog.emit("taskDetail.event", "taskID=\(taskID) event=\(String(describing: event))")
        loadMachine.send(event, run: { [syncEngine, taskID] in
            try await syncEngine.syncTaskDetail(taskID: taskID)
        })
    }

    private func debugTaskSnapshot(_ task: Task?) -> String {
        guard let task else {
            return "taskID=\(taskID) task=nil"
        }
        return [
            "taskID=\(task.id)",
            "authorID=\(task.authorID)",
            "author=\(task.author?.id ?? "nil")",
            "assigneeID=\(task.assigneeID ?? "nil")",
            "assignee=\(task.assignee?.id ?? "nil")",
            "reviewers=\(task.reviewers.map(\.id).sorted())",
            "watchers=\(task.watchers.map(\.id).sorted())",
            "items=\(task.items.map(\.id).sorted())"
        ].joined(separator: " ")
    }

}

@MainActor
@Observable
public final class TaskFormMachine {
    public private(set) var users: [User] = []
    public private(set) var taskStateOptions: [TaskStateOption] = []
    public private(set) var metadataLoadState: ScreenLoadState = .idle
    public private(set) var saveState: SubmissionState = .idle

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
            if draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.descriptionText = "No description yet."
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
