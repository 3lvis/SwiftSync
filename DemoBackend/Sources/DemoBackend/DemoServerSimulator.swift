import Foundation
import SQLite3

public enum DemoBackendError: LocalizedError {
    case openDatabase(String)
    case sqlite(message: String)
    case notFound(entity: String, id: String)
    case invalidReference(entity: String, id: String)
    case validation(message: String)

    public var errorDescription: String? {
        switch self {
        case let .openDatabase(path):
            return "Failed to open demo backend database at \(path)."
        case let .sqlite(message):
            return "SQLite error: \(message)"
        case let .notFound(entity, id):
            return "\(entity) not found: \(id)"
        case let .invalidReference(entity, id):
            return "Invalid reference \(entity)=\(id)"
        case let .validation(message):
            return "Validation error: \(message)"
        }
    }
}

public final class DemoServerSimulator {
    private struct ChecklistItemInput {
        let id: String
        let title: String
        let position: Int
        let createdAt: Date
        let updatedAt: Date
    }

    private let sqlite: DemoSQLiteDatabase
    private let formatter = ISO8601DateFormatter()
    private let enableAmbientProjectMutationsOnRead: Bool
    private var ambientProjectReadCounters: [String: Int] = [:]
    private var ambientMutationsSuspendedUntil: Date?

    public init(
        databaseURL: URL,
        seedData: DemoSeedData,
        enableAmbientProjectMutationsOnRead: Bool = false
    ) throws {
        self.sqlite = try DemoSQLiteDatabase(databaseURL: databaseURL)
        self.enableAmbientProjectMutationsOnRead = enableAmbientProjectMutationsOnRead
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try self.sqlite.execute("PRAGMA foreign_keys = ON;")
        try Self.prepareSchema(self.sqlite, seedData: seedData)
    }

    public func getProjectsPayload() throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT
                projects.id,
                projects.name,
                projects.created_at,
                projects.updated_at,
                COUNT(tasks.id) AS task_count
            FROM projects
            LEFT JOIN tasks ON tasks.project_id = projects.id
            GROUP BY projects.id, projects.name, projects.created_at, projects.updated_at
            ORDER BY projects.id ASC
            """
        )
        return rows.map { row in
            [
                "id": row.string("id"),
                "name": row.string("name"),
                "task_count": Int(row.int64("task_count")),
                "created_at": iso8601(row.double("created_at")),
                "updated_at": iso8601(row.double("updated_at"))
            ]
        }
    }

    public func getProjectTasksPayload(projectID: String) throws -> [[String: Any]] {
        if enableAmbientProjectMutationsOnRead, shouldApplyAmbientProjectMutationOnRead() {
            let next = (ambientProjectReadCounters[projectID] ?? 0) + 1
            ambientProjectReadCounters[projectID] = next
            // Slow the ambient "alive backend" effect so user-triggered refreshes remain readable.
            if next.isMultiple(of: 2) {
                try applyAmbientProjectMutation(projectID: projectID, step: next)
            }
        }

        return try getProjectTasksPayloadRaw(projectID: projectID)
    }

    private func getProjectTasksPayloadRaw(projectID: String) throws -> [[String: Any]] {
        try getTasksPayload(
            whereClause: "WHERE project_id = ?",
            bind: { stmt in self.sqlite.bind(text: projectID, at: 1, in: stmt) }
        )
    }

    public func getUsersPayload() throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT id, display_name, role, created_at, updated_at
            FROM users
            ORDER BY id ASC
            """
        )
        return rows.map { row in
            [
                "id": row.string("id"),
                "display_name": row.string("display_name"),
                "role": labeledValuePayload(id: row.string("role"), label: row.string("role")),
                "created_at": iso8601(row.double("created_at")),
                "updated_at": iso8601(row.double("updated_at"))
            ]
        }
    }

    public func getTaskStateOptionsPayload() throws -> [[String: Any]] {
        let timestamp = iso8601(0)
        return [
            [
                "id": "todo",
                "label": "To Do",
                "sort_order": 0,
                "created_at": timestamp,
                "updated_at": timestamp
            ],
            [
                "id": "inProgress",
                "label": "In Progress",
                "sort_order": 1,
                "created_at": timestamp,
                "updated_at": timestamp
            ],
            [
                "id": "done",
                "label": "Done",
                "sort_order": 2,
                "created_at": timestamp,
                "updated_at": timestamp
            ]
        ]
    }

    public func getUserRoleOptionsPayload() throws -> [[String: Any]] {
        try optionsPayload(
            rows: self.sqlite.query(
                """
                SELECT DISTINCT role AS id
                FROM users
                ORDER BY role ASC
                """
            )
        )
    }

    public func getTaskDetailPayload(taskID: String) throws -> [String: Any]? {
        let rows = try self.sqlite.query(
            """
            SELECT id, project_id, assignee_id, author_id, title, description, state, created_at, updated_at
            FROM tasks
            WHERE id = ?
            LIMIT 1
            """,
            bind: { stmt in
                self.sqlite.bind(text: taskID, at: 1, in: stmt)
            }
        )
        guard let row = rows.first else { return nil }
        return try taskPayload(from: row)
    }

    @discardableResult
    public func patchTaskDescription(taskID: String, descriptionText: String) throws -> [String: Any]? {
        guard let current = try getTaskDetailPayload(taskID: taskID) else { return nil }
        suspendAmbientMutationsAfterWrite()
        let currentUpdatedAt = try parseISO8601(current["updated_at"])
        let next = nextTimestamp(after: currentUpdatedAt)

        try self.sqlite.execute(
            """
            UPDATE tasks
            SET description = ?, updated_at = ?
            WHERE id = ?
            """,
            bind: { stmt in
                self.sqlite.bind(text: descriptionText, at: 1, in: stmt)
                self.sqlite.bind(double: next.timeIntervalSince1970, at: 2, in: stmt)
                self.sqlite.bind(text: taskID, at: 3, in: stmt)
            }
        )
        return try getTaskDetailPayload(taskID: taskID)
    }

    @discardableResult
    public func patchTaskState(taskID: String, state: String) throws -> [String: Any]? {
        _ = try validatedTaskState(state)
        guard let current = try getTaskDetailPayload(taskID: taskID) else { return nil }
        suspendAmbientMutationsAfterWrite()
        let currentUpdatedAt = try parseISO8601(current["updated_at"])
        let next = nextTimestamp(after: currentUpdatedAt)

        try self.sqlite.execute(
            """
            UPDATE tasks
            SET state = ?, updated_at = ?
            WHERE id = ?
            """,
            bind: { stmt in
                self.sqlite.bind(text: state, at: 1, in: stmt)
                self.sqlite.bind(double: next.timeIntervalSince1970, at: 2, in: stmt)
                self.sqlite.bind(text: taskID, at: 3, in: stmt)
            }
        )
        return try getTaskDetailPayload(taskID: taskID)
    }

    @discardableResult
    public func patchTaskAssignee(taskID: String, assigneeID: String?) throws -> [String: Any]? {
        if let assigneeID, !(try exists(in: "users", id: assigneeID)) {
            throw DemoBackendError.invalidReference(entity: "assignee_id", id: assigneeID)
        }
        guard let current = try getTaskDetailPayload(taskID: taskID) else { return nil }
        suspendAmbientMutationsAfterWrite()
        let currentUpdatedAt = try parseISO8601(current["updated_at"])
        let next = nextTimestamp(after: currentUpdatedAt)

        try self.sqlite.execute(
            """
            UPDATE tasks
            SET assignee_id = ?, updated_at = ?
            WHERE id = ?
            """,
            bind: { stmt in
                self.sqlite.bind(nullableText: assigneeID, at: 1, in: stmt)
                self.sqlite.bind(double: next.timeIntervalSince1970, at: 2, in: stmt)
                self.sqlite.bind(text: taskID, at: 3, in: stmt)
            }
        )
        return try getTaskDetailPayload(taskID: taskID)
    }

    @discardableResult
    public func replaceTaskReviewers(taskID: String, reviewerIDs: [String]) throws -> [String: Any]? {
        guard try exists(in: "tasks", id: taskID) else { return nil }
        let uniqueReviewerIDs = Array(Set(reviewerIDs)).sorted()
        for reviewerID in uniqueReviewerIDs where !(try exists(in: "users", id: reviewerID)) {
            throw DemoBackendError.invalidReference(entity: "reviewer_id", id: reviewerID)
        }

        guard let current = try getTaskDetailPayload(taskID: taskID) else { return nil }
        suspendAmbientMutationsAfterWrite()
        let currentUpdatedAt = try parseISO8601(current["updated_at"])
        let next = nextTimestamp(after: currentUpdatedAt)

        try self.sqlite.execute("BEGIN TRANSACTION;")
        do {
            try self.sqlite.execute(
                "DELETE FROM task_reviewers WHERE task_id = ?",
                bind: { stmt in
                    self.sqlite.bind(text: taskID, at: 1, in: stmt)
                }
            )

            for reviewerID in uniqueReviewerIDs {
                try self.sqlite.execute(
                    """
                    INSERT INTO task_reviewers (task_id, user_id)
                    VALUES (?, ?)
                    """,
                    bind: { stmt in
                        self.sqlite.bind(text: taskID, at: 1, in: stmt)
                        self.sqlite.bind(text: reviewerID, at: 2, in: stmt)
                    }
                )
            }

            try self.sqlite.execute(
                """
                UPDATE tasks
                SET updated_at = ?
                WHERE id = ?
                """,
                bind: { stmt in
                    self.sqlite.bind(double: next.timeIntervalSince1970, at: 1, in: stmt)
                    self.sqlite.bind(text: taskID, at: 2, in: stmt)
                }
            )
            try self.sqlite.execute("COMMIT;")
        } catch {
            try? self.sqlite.execute("ROLLBACK;")
            throw error
        }

        return try getTaskDetailPayload(taskID: taskID)
    }

    @discardableResult
    public func replaceTaskWatchers(taskID: String, watcherIDs: [String]) throws -> [String: Any]? {
        guard try exists(in: "tasks", id: taskID) else { return nil }
        let uniqueWatcherIDs = Array(Set(watcherIDs)).sorted()
        for watcherID in uniqueWatcherIDs where !(try exists(in: "users", id: watcherID)) {
            throw DemoBackendError.invalidReference(entity: "watcher_id", id: watcherID)
        }

        guard let current = try getTaskDetailPayload(taskID: taskID) else { return nil }
        suspendAmbientMutationsAfterWrite()
        let currentUpdatedAt = try parseISO8601(current["updated_at"])
        let next = nextTimestamp(after: currentUpdatedAt)

        try self.sqlite.execute("BEGIN TRANSACTION;")
        do {
            try self.sqlite.execute(
                "DELETE FROM task_watchers WHERE task_id = ?",
                bind: { stmt in
                    self.sqlite.bind(text: taskID, at: 1, in: stmt)
                }
            )

            for watcherID in uniqueWatcherIDs {
                try self.sqlite.execute(
                    """
                    INSERT INTO task_watchers (task_id, user_id)
                    VALUES (?, ?)
                    """,
                    bind: { stmt in
                        self.sqlite.bind(text: taskID, at: 1, in: stmt)
                        self.sqlite.bind(text: watcherID, at: 2, in: stmt)
                    }
                )
            }

            try self.sqlite.execute(
                """
                UPDATE tasks
                SET updated_at = ?
                WHERE id = ?
                """,
                bind: { stmt in
                    self.sqlite.bind(double: next.timeIntervalSince1970, at: 1, in: stmt)
                    self.sqlite.bind(text: taskID, at: 2, in: stmt)
                }
            )
            try self.sqlite.execute("COMMIT;")
        } catch {
            try? self.sqlite.execute("ROLLBACK;")
            throw error
        }

        return try getTaskDetailPayload(taskID: taskID)
    }

    public func createTask(body: [String: Any]) throws -> [String: Any] {
        guard let id = body["id"] as? String, !id.isEmpty else {
            throw DemoBackendError.validation(message: "id is required")
        }
        guard let projectID = body["project_id"] as? String else {
            throw DemoBackendError.validation(message: "project_id is required")
        }
        guard let title = body["title"] as? String else {
            throw DemoBackendError.validation(message: "title is required")
        }
        guard let description = body["description"] as? String else {
            throw DemoBackendError.validation(message: "description is required")
        }
        guard let stateDict = body["state"] as? [String: Any],
              let stateID = stateDict["id"] as? String else {
            throw DemoBackendError.validation(message: "state.id is required")
        }
        guard let authorID = body["author_id"] as? String else {
            throw DemoBackendError.validation(message: "author_id is required")
        }
        guard let createdAtString = body["created_at"] as? String,
              let createdAt = parseISO8601String(createdAtString) else {
            throw DemoBackendError.validation(message: "created_at is required (ISO 8601)")
        }
        guard let updatedAtString = body["updated_at"] as? String,
              let updatedAt = parseISO8601String(updatedAtString) else {
            throw DemoBackendError.validation(message: "updated_at is required (ISO 8601)")
        }
        let assigneeID = body["assignee_id"] as? String
        let checklistItems: [ChecklistItemInput]
        if body.keys.contains("checklist_items") {
            guard let rawChecklistItems = body["checklist_items"] as? [[String: Any]] else {
                throw DemoBackendError.validation(message: "checklist_items must be an array of objects")
            }
            checklistItems = try parseChecklistItems(rawChecklistItems)
        } else {
            checklistItems = []
        }

        return try createTaskInternal(
            id: id,
            projectID: projectID,
            title: title,
            descriptionText: description,
            state: stateID,
            assigneeID: assigneeID,
            authorID: authorID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            checklistItems: checklistItems
        )
    }

    private func createTaskInternal(
        id: String,
        projectID: String,
        title: String,
        descriptionText: String,
        state: String,
        assigneeID: String?,
        authorID: String,
        createdAt: Date,
        updatedAt: Date,
        checklistItems: [ChecklistItemInput] = []
    ) throws -> [String: Any] {
        if try exists(in: "tasks", id: id) {
            throw DemoBackendError.validation(message: "task with id \(id) already exists")
        }
        guard try exists(in: "projects", id: projectID) else {
            throw DemoBackendError.invalidReference(entity: "project_id", id: projectID)
        }
        if let assigneeID, !(try exists(in: "users", id: assigneeID)) {
            throw DemoBackendError.invalidReference(entity: "assignee_id", id: assigneeID)
        }
        if !(try exists(in: "users", id: authorID)) {
            throw DemoBackendError.invalidReference(entity: "author_id", id: authorID)
        }
        let normalizedTitle = try validatedNonEmpty(title, field: "title")
        let normalizedDescription = try validatedNonEmpty(descriptionText, field: "description")
        let normalizedState = try validatedTaskState(state)

        suspendAmbientMutationsAfterWrite()

        try self.sqlite.execute("BEGIN TRANSACTION;")
        do {
            try self.sqlite.execute(
                """
                INSERT INTO tasks (id, project_id, assignee_id, author_id, title, description, state, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bind: { stmt in
                    self.sqlite.bind(text: id, at: 1, in: stmt)
                    self.sqlite.bind(text: projectID, at: 2, in: stmt)
                    self.sqlite.bind(nullableText: assigneeID, at: 3, in: stmt)
                    self.sqlite.bind(text: authorID, at: 4, in: stmt)
                    self.sqlite.bind(text: normalizedTitle, at: 5, in: stmt)
                    self.sqlite.bind(text: normalizedDescription, at: 6, in: stmt)
                    self.sqlite.bind(text: normalizedState, at: 7, in: stmt)
                    self.sqlite.bind(double: createdAt.timeIntervalSince1970, at: 8, in: stmt)
                    self.sqlite.bind(double: updatedAt.timeIntervalSince1970, at: 9, in: stmt)
                }
            )

            try insertChecklistItems(checklistItems, forTaskID: id)
            try self.sqlite.execute("COMMIT;")
        } catch {
            try? self.sqlite.execute("ROLLBACK;")
            throw error
        }

        guard let payload = try getTaskDetailPayload(taskID: id) else {
            throw DemoBackendError.notFound(entity: "task", id: id)
        }
        return payload
    }

    /// PUT /tasks/:id — full-object update. Accepts the same field shape that createTask produces
    /// (exported via SwiftSync's exportObject), reads all mutable scalar fields, and applies them.
    /// id, project_id, author_id, and created_at are immutable; they are validated for consistency
    /// but not updated. updated_at is always advanced by the server regardless of the incoming value.
    @discardableResult
    public func updateTask(taskID: String, body: [String: Any]) throws -> [String: Any] {
        guard let current = try getTaskDetailPayload(taskID: taskID) else {
            throw DemoBackendError.notFound(entity: "task", id: taskID)
        }

        // Validate immutable field consistency
        if let incomingID = body["id"] as? String, incomingID != taskID {
            throw DemoBackendError.validation(message: "id in body does not match taskID")
        }

        guard let title = body["title"] as? String else {
            throw DemoBackendError.validation(message: "title is required")
        }
        guard let description = body["description"] as? String else {
            throw DemoBackendError.validation(message: "description is required")
        }
        guard let stateDict = body["state"] as? [String: Any],
              let stateID = stateDict["id"] as? String else {
            throw DemoBackendError.validation(message: "state.id is required")
        }

        let normalizedTitle = try validatedNonEmpty(title, field: "title")
        let normalizedDescription = try validatedNonEmpty(description, field: "description")
        let normalizedState = try validatedTaskState(stateID)
        let checklistItemsToReplace: [ChecklistItemInput]?
        if body.keys.contains("checklist_items") {
            guard let rawChecklistItems = body["checklist_items"] as? [[String: Any]] else {
                throw DemoBackendError.validation(message: "checklist_items must be an array of objects")
            }
            checklistItemsToReplace = try parseChecklistItems(rawChecklistItems)
        } else {
            checklistItemsToReplace = nil
        }

        // assignee_id: present key means update (NSNull clears, String sets)
        let assigneeID: String?
        if body.keys.contains("assignee_id") {
            assigneeID = body["assignee_id"] as? String   // nil if NSNull
        } else {
            // Preserve current value if key is absent
            assigneeID = current["assignee_id"] as? String
        }

        if let assigneeID, !(try exists(in: "users", id: assigneeID)) {
            throw DemoBackendError.invalidReference(entity: "assignee_id", id: assigneeID)
        }

        suspendAmbientMutationsAfterWrite()
        let currentUpdatedAt = try parseISO8601(current["updated_at"])
        let next = nextTimestamp(after: currentUpdatedAt)

        try self.sqlite.execute("BEGIN TRANSACTION;")
        do {
            try self.sqlite.execute(
                """
                UPDATE tasks
                SET title = ?, description = ?, state = ?, assignee_id = ?, updated_at = ?
                WHERE id = ?
                """,
                bind: { stmt in
                    self.sqlite.bind(text: normalizedTitle, at: 1, in: stmt)
                    self.sqlite.bind(text: normalizedDescription, at: 2, in: stmt)
                    self.sqlite.bind(text: normalizedState, at: 3, in: stmt)
                    self.sqlite.bind(nullableText: assigneeID, at: 4, in: stmt)
                    self.sqlite.bind(double: next.timeIntervalSince1970, at: 5, in: stmt)
                    self.sqlite.bind(text: taskID, at: 6, in: stmt)
                }
            )

            if let checklistItemsToReplace {
                try self.sqlite.execute(
                    "DELETE FROM checklist_items WHERE task_id = ?",
                    bind: { stmt in
                        self.sqlite.bind(text: taskID, at: 1, in: stmt)
                    }
                )
                try insertChecklistItems(checklistItemsToReplace, forTaskID: taskID)
            }

            try self.sqlite.execute("COMMIT;")
        } catch {
            try? self.sqlite.execute("ROLLBACK;")
            throw error
        }

        guard let result = try getTaskDetailPayload(taskID: taskID) else {
            throw DemoBackendError.notFound(entity: "task", id: taskID)
        }
        return result
    }

    public func deleteTask(taskID: String) throws {
        guard try exists(in: "tasks", id: taskID) else {
            throw DemoBackendError.notFound(entity: "task", id: taskID)
        }
        suspendAmbientMutationsAfterWrite()
        try self.sqlite.execute(
            "DELETE FROM tasks WHERE id = ?",
            bind: { stmt in
                self.sqlite.bind(text: taskID, at: 1, in: stmt)
            }
        )
    }

    private func applyAmbientProjectMutation(projectID: String, step: Int) throws {
        guard try exists(in: "projects", id: projectID) else { return }

        let currentTasks = try getProjectTasksPayloadRaw(projectID: projectID)
        let operation = step % 3

        switch operation {
        case 0:
            try ambientUpdateTask(in: projectID, tasks: currentTasks, step: step)
        case 1:
            try ambientCreateTask(in: projectID, step: step)
        default:
            if currentTasks.count > 2 {
                try ambientDeleteTask(tasks: currentTasks, step: step)
            } else {
                try ambientUpdateTask(in: projectID, tasks: currentTasks, step: step)
            }
        }
    }

    private func getTasksPayload(
        whereClause: String,
        bind: ((OpaquePointer?) throws -> Void)?
    ) throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT tasks.id, tasks.project_id, tasks.assignee_id, tasks.author_id, tasks.title, tasks.description, tasks.state, tasks.created_at, tasks.updated_at
            FROM tasks
            \(whereClause)
            ORDER BY tasks.id ASC
            """,
            bind: bind
        )
        return try rows.map(taskPayload(from:))
    }

    private func ambientUpdateTask(in projectID: String, tasks: [[String: Any]], step: Int) throws {
        guard !tasks.isEmpty else {
            try ambientCreateTask(in: projectID, step: step)
            return
        }

        let task = tasks[step % tasks.count]
        guard let taskID = task["id"] as? String else { return }
        let updateKind = (step / 3) % 2

        if updateKind == 0 {
            let currentState = ((task["state"] as? [String: Any])?["id"] as? String) ?? "todo"
            let nextState: String
            switch currentState {
            case "todo":
                nextState = "inProgress"
            case "inProgress":
                nextState = "done"
            default:
                nextState = "todo"
            }
            _ = try patchTaskState(taskID: taskID, state: nextState)
        } else {
            let userIDs = try allIDs(in: "users")
            guard !userIDs.isEmpty else { return }
            let shouldClear = (step % 5) == 0
            if shouldClear {
                _ = try patchTaskAssignee(taskID: taskID, assigneeID: nil)
            } else {
                let assigneeID = userIDs[(step / 2) % userIDs.count]
                _ = try patchTaskAssignee(taskID: taskID, assigneeID: assigneeID)
            }
        }
    }

    private func ambientCreateTask(in projectID: String, step: Int) throws {
        let userIDs = try allIDs(in: "users")
        guard !userIDs.isEmpty else { return }

        let titles = [
            "Review sync behavior after background refresh",
            "Tighten payload validation before rollout",
            "Polish empty state after scoped delete",
            "Add regression check for task list animation",
            "Confirm assignee clear flow matches API contract",
            "Re-run parent-scoped sync smoke test"
        ]
        let states = ["todo", "inProgress", "done"]
        let selectedTitle = titles[step % titles.count]
        let state = states[(step / 2) % states.count]
        let assigneeID: String? = (step % 4 == 0) ? nil : userIDs[step % userIDs.count]
        let authorID = assigneeID ?? userIDs.first!

        let now = Date()
        _ = try createTaskInternal(
            id: UUID().uuidString,
            projectID: projectID,
            title: selectedTitle,
            descriptionText: "Ambient backend update generated for the demo live-sync effect.",
            state: state,
            assigneeID: assigneeID,
            authorID: authorID,
            createdAt: now,
            updatedAt: now
        )
    }

    private func ambientDeleteTask(tasks: [[String: Any]], step: Int) throws {
        guard !tasks.isEmpty else { return }
        let task = tasks[(step / 2) % tasks.count]
        guard let taskID = task["id"] as? String else { return }
        try deleteTask(taskID: taskID)
    }

    private func taskPayload(from row: DemoSQLiteRow) throws -> [String: Any] {
        let taskID = row.string("id")
        let stateID = row.string("state")
        return [
            "id": taskID,
            "project_id": row.string("project_id"),
            "assignee_id": row.nullableString("assignee_id") ?? NSNull(),
            "reviewer_ids": try reviewerIDsFor(taskID: taskID),
            "author_id": row.string("author_id"),
            "title": row.string("title"),
            "description": row.string("description"),
            "state": labeledValuePayload(id: stateID, label: taskStateLabel(id: stateID)),
            "watcher_ids": try watcherIDs(forTaskID: taskID),
            "checklist_items": try checklistItemsPayload(taskID: taskID),
            "created_at": iso8601(row.double("created_at")),
            "updated_at": iso8601(row.double("updated_at"))
        ]
    }

    private func checklistItemsPayload(taskID: String) throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT id, task_id, title, position, created_at, updated_at
            FROM checklist_items
            WHERE task_id = ?
            ORDER BY position ASC, id ASC
            """,
            bind: { stmt in
                self.sqlite.bind(text: taskID, at: 1, in: stmt)
            }
        )
        return rows.map { row in
            [
                "id": row.string("id"),
                "task_id": row.string("task_id"),
                "title": row.string("title"),
                "position": Int(row.int64("position")),
                "created_at": iso8601(row.double("created_at")),
                "updated_at": iso8601(row.double("updated_at"))
            ]
        }
    }

    private func taskStateLabel(id stateID: String) -> String {
        switch stateID {
        case "todo": "To Do"
        case "inProgress": "In Progress"
        case "done": "Done"
        default: stateID
        }
    }

    private func labeledValuePayload(id: String, label: String) -> [String: Any] {
        [
            "id": id,
            "label": label
        ]
    }

    private func optionsPayload(rows: [DemoSQLiteRow]) throws -> [[String: Any]] {
        let timestamp = iso8601(0)
        return rows.enumerated().map { index, row in
            let id = row.string("id")
            return [
                "id": id,
                "label": id,
                "sort_order": index,
                "created_at": timestamp,
                "updated_at": timestamp
            ]
        }
    }

    private func reviewerIDsFor(taskID: String) throws -> [String] {
        let rows = try self.sqlite.query(
            """
            SELECT user_id
            FROM task_reviewers
            WHERE task_id = ?
            ORDER BY user_id ASC
            """,
            bind: { stmt in
                self.sqlite.bind(text: taskID, at: 1, in: stmt)
            }
        )
        return rows.map { $0.string("user_id") }
    }

    private func watcherIDs(forTaskID taskID: String) throws -> [String] {
        let rows = try self.sqlite.query(
            """
            SELECT user_id
            FROM task_watchers
            WHERE task_id = ?
            ORDER BY user_id ASC
            """,
            bind: { stmt in
                self.sqlite.bind(text: taskID, at: 1, in: stmt)
            }
        )
        return rows.map { $0.string("user_id") }
    }

    private func parseChecklistItems(_ rawChecklistItems: [[String: Any]]) throws -> [ChecklistItemInput] {
        try rawChecklistItems.enumerated().map { index, item in
            guard let id = item["id"] as? String, !id.isEmpty else {
                throw DemoBackendError.validation(message: "checklist_items[\(index)].id is required")
            }
            guard let rawTitle = item["title"] as? String else {
                throw DemoBackendError.validation(message: "checklist_items[\(index)].title is required")
            }
            let title = try validatedNonEmpty(rawTitle, field: "checklist_items[\(index)].title")

            let position: Int
            if let positionValue = item["position"] {
                guard let parsedPosition = positionValue as? Int else {
                    throw DemoBackendError.validation(message: "checklist_items[\(index)].position must be an Int")
                }
                position = parsedPosition
            } else {
                position = index
            }

            let createdAt: Date
            if let createdAtValue = item["created_at"] {
                guard let createdAtString = createdAtValue as? String,
                      let parsedCreatedAt = parseISO8601String(createdAtString) else {
                    throw DemoBackendError.validation(message: "checklist_items[\(index)].created_at must be ISO 8601")
                }
                createdAt = parsedCreatedAt
            } else {
                createdAt = Date()
            }

            let updatedAt: Date
            if let updatedAtValue = item["updated_at"] {
                guard let updatedAtString = updatedAtValue as? String,
                      let parsedUpdatedAt = parseISO8601String(updatedAtString) else {
                    throw DemoBackendError.validation(message: "checklist_items[\(index)].updated_at must be ISO 8601")
                }
                updatedAt = parsedUpdatedAt
            } else {
                updatedAt = Date()
            }

            return ChecklistItemInput(
                id: id,
                title: title,
                position: position,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    private func insertChecklistItems(_ checklistItems: [ChecklistItemInput], forTaskID taskID: String) throws {
        for item in checklistItems {
            try self.sqlite.execute(
                """
                INSERT INTO checklist_items (id, task_id, title, position, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                bind: { stmt in
                    self.sqlite.bind(text: item.id, at: 1, in: stmt)
                    self.sqlite.bind(text: taskID, at: 2, in: stmt)
                    self.sqlite.bind(text: item.title, at: 3, in: stmt)
                    sqlite3_bind_int64(stmt, 4, Int64(item.position))
                    self.sqlite.bind(double: item.createdAt.timeIntervalSince1970, at: 5, in: stmt)
                    self.sqlite.bind(double: item.updatedAt.timeIntervalSince1970, at: 6, in: stmt)
                }
            )
        }
    }

    private func exists(in table: String, id: String) throws -> Bool {
        let rows = try self.sqlite.query(
            "SELECT 1 AS one FROM \(table) WHERE id = ? LIMIT 1",
            bind: { stmt in
                self.sqlite.bind(text: id, at: 1, in: stmt)
            }
        )
        return !rows.isEmpty
    }

    private func allIDs(in table: String) throws -> [String] {
        let rows = try self.sqlite.query(
            "SELECT id FROM \(table) ORDER BY id ASC"
        )
        return rows.map { $0.string("id") }
    }

    private func validatedNonEmpty(_ value: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DemoBackendError.validation(message: "\(field) must not be empty")
        }
        return trimmed
    }

    private func validatedTaskState(_ state: String) throws -> String {
        let allowed = ["todo", "inProgress", "done"]
        guard allowed.contains(state) else {
            throw DemoBackendError.validation(message: "state must be one of \(allowed.joined(separator: ", "))")
        }
        return state
    }

    private func parseISO8601(_ value: Any?) throws -> Date? {
        guard let string = value as? String else { return nil }
        if let date = formatter.date(from: string) {
            return date
        }
        throw DemoBackendError.sqlite(message: "Invalid ISO-8601 timestamp in payload: \(string)")
    }

    private func parseISO8601String(_ string: String) -> Date? {
        formatter.date(from: string)
    }

    private func nextTimestamp(after previous: Date?) -> Date {
        let now = Date()
        if let previous {
            return max(now, previous.addingTimeInterval(0.001))
        }
        return now
    }

    private func iso8601(_ secondsSince1970: Double) -> String {
        formatter.string(from: Date(timeIntervalSince1970: secondsSince1970))
    }

    private func shouldApplyAmbientProjectMutationOnRead() -> Bool {
        guard let suspendedUntil = ambientMutationsSuspendedUntil else { return true }
        return Date() >= suspendedUntil
    }

    private func suspendAmbientMutationsAfterWrite() {
        ambientMutationsSuspendedUntil = Date().addingTimeInterval(1.25)
    }

    private static func prepareSchema(_ sqlite: DemoSQLiteDatabase, seedData: DemoSeedData) throws {
        try createSchemaIfNeeded(sqlite: sqlite)
        try seedIfNeeded(sqlite, seedData: seedData)
    }

    private static func createSchemaIfNeeded(sqlite: DemoSQLiteDatabase) throws {
        try sqlite.executeScript(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                role TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                assignee_id TEXT NULL,
                author_id TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                state TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE RESTRICT,
                FOREIGN KEY(assignee_id) REFERENCES users(id) ON DELETE SET NULL,
                FOREIGN KEY(author_id) REFERENCES users(id) ON DELETE RESTRICT
            );

            CREATE TABLE IF NOT EXISTS task_reviewers (
                task_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                PRIMARY KEY (task_id, user_id),
                FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS task_watchers (
                task_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                PRIMARY KEY (task_id, user_id),
                FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS checklist_items (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                title TEXT NOT NULL,
                position INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
            );

            """
        )
    }

    private static func seedIfNeeded(_ sqlite: DemoSQLiteDatabase, seedData: DemoSeedData) throws {
        let rows = try sqlite.query("SELECT COUNT(*) AS count FROM projects")
        let projectCount = Int(rows.first?.int64("count") ?? 0)
        guard projectCount == 0 else { return }

        try sqlite.execute("BEGIN TRANSACTION;")
        do {
            for project in seedData.projects {
            try sqlite.execute(
                """
                INSERT INTO projects (id, name, created_at, updated_at)
                VALUES (?, ?, ?, ?)
                """,
                bind: { stmt in
                    sqlite.bind(text: project.id, at: 1, in: stmt)
                    sqlite.bind(text: project.name, at: 2, in: stmt)
                    sqlite.bind(double: project.createdAt.timeIntervalSince1970, at: 3, in: stmt)
                    sqlite.bind(double: project.updatedAt.timeIntervalSince1970, at: 4, in: stmt)
                }
            )
            }

            for user in seedData.users {
                try sqlite.execute(
                    """
                    INSERT INTO users (id, display_name, role, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: user.id, at: 1, in: stmt)
                        sqlite.bind(text: user.displayName, at: 2, in: stmt)
                        sqlite.bind(text: user.role, at: 3, in: stmt)
                        sqlite.bind(double: user.createdAt.timeIntervalSince1970, at: 4, in: stmt)
                        sqlite.bind(double: user.updatedAt.timeIntervalSince1970, at: 5, in: stmt)
                    }
                )
            }

            for task in seedData.tasks {
                try sqlite.execute(
                    """
                    INSERT INTO tasks (id, project_id, assignee_id, author_id, title, description, state, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: task.id, at: 1, in: stmt)
                        sqlite.bind(text: task.projectID, at: 2, in: stmt)
                        sqlite.bind(nullableText: task.assigneeID, at: 3, in: stmt)
                        sqlite.bind(text: task.authorID, at: 4, in: stmt)
                        sqlite.bind(text: task.title, at: 5, in: stmt)
                        sqlite.bind(text: task.descriptionText, at: 6, in: stmt)
                        sqlite.bind(text: task.state, at: 7, in: stmt)
                        sqlite.bind(double: task.createdAt.timeIntervalSince1970, at: 8, in: stmt)
                        sqlite.bind(double: task.updatedAt.timeIntervalSince1970, at: 9, in: stmt)
                    }
                )

                for reviewerID in task.reviewerIDs {
                    try sqlite.execute(
                        """
                        INSERT INTO task_reviewers (task_id, user_id)
                        VALUES (?, ?)
                        """,
                        bind: { stmt in
                            sqlite.bind(text: task.id, at: 1, in: stmt)
                            sqlite.bind(text: reviewerID, at: 2, in: stmt)
                        }
                    )
                }

                for watcherID in task.watcherIDs {
                    try sqlite.execute(
                        """
                        INSERT INTO task_watchers (task_id, user_id)
                        VALUES (?, ?)
                        """,
                        bind: { stmt in
                            sqlite.bind(text: task.id, at: 1, in: stmt)
                            sqlite.bind(text: watcherID, at: 2, in: stmt)
                        }
                    )
                }
            }

            for item in seedData.checklistItems {
                try sqlite.execute(
                    """
                    INSERT INTO checklist_items (id, task_id, title, position, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: item.id, at: 1, in: stmt)
                        sqlite.bind(text: item.taskID, at: 2, in: stmt)
                        sqlite.bind(text: item.title, at: 3, in: stmt)
                        sqlite3_bind_int64(stmt, 4, Int64(item.position))
                        sqlite.bind(double: item.createdAt.timeIntervalSince1970, at: 5, in: stmt)
                        sqlite.bind(double: item.updatedAt.timeIntervalSince1970, at: 6, in: stmt)
                    }
                )
            }

            try sqlite.execute("COMMIT;")
        } catch {
            try? sqlite.execute("ROLLBACK;")
            throw error
        }
    }
}

private final class DemoSQLiteDatabase {
    private var db: OpaquePointer?

    init(databaseURL: URL) throws {
        let path = databaseURL.path
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            defer { sqlite3_close(db) }
            throw DemoBackendError.openDatabase(path)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(stmt) }

        if let bind {
            try bind(stmt)
        }

        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw sqliteError()
        }
    }

    func executeScript(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard rc == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown sqlite3_exec error"
            sqlite3_free(errorMessage)
            throw DemoBackendError.sqlite(message: message)
        }
    }

    func query(_ sql: String, bind: ((OpaquePointer?) throws -> Void)? = nil) throws -> [DemoSQLiteRow] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        defer { sqlite3_finalize(stmt) }

        if let bind {
            try bind(stmt)
        }

        var rows: [DemoSQLiteRow] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                rows.append(DemoSQLiteRow(statement: stmt))
                continue
            }
            if rc == SQLITE_DONE {
                break
            }
            throw sqliteError()
        }
        return rows
    }

    func bind(text value: String, at index: Int32, in stmt: OpaquePointer?) {
        _ = value.withCString { cString in
            sqlite3_bind_text(stmt, index, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    func bind(nullableText value: String?, at index: Int32, in stmt: OpaquePointer?) {
        if let value {
            bind(text: value, at: index, in: stmt)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    func bind(double value: Double, at index: Int32, in stmt: OpaquePointer?) {
        sqlite3_bind_double(stmt, index, value)
    }

    private func sqliteError() -> DemoBackendError {
        let message = String(cString: sqlite3_errmsg(db))
        return .sqlite(message: message)
    }
}

private struct DemoSQLiteRow {
    private let values: [String: DemoSQLiteValue]

    init(statement: OpaquePointer?) {
        let columnCount = sqlite3_column_count(statement)
        var values: [String: DemoSQLiteValue] = [:]
        values.reserveCapacity(Int(columnCount))

        for index in 0..<columnCount {
            let name = String(cString: sqlite3_column_name(statement, index))
            values[name] = DemoSQLiteValue(statement: statement, index: index)
        }
        self.values = values
    }

    func string(_ key: String) -> String {
        guard case let .string(value)? = values[key] else { return "" }
        return value
    }

    func nullableString(_ key: String) -> String? {
        guard let value = values[key] else { return nil }
        switch value {
        case let .string(string):
            return string
        case .null:
            return nil
        case let .int64(number):
            return String(number)
        case let .double(number):
            return String(number)
        }
    }

    func int64(_ key: String) -> Int64 {
        guard let value = values[key] else { return 0 }
        switch value {
        case let .int64(number):
            return number
        case let .double(number):
            return Int64(number)
        case let .string(string):
            return Int64(string) ?? 0
        case .null:
            return 0
        }
    }

    func double(_ key: String) -> Double {
        guard let value = values[key] else { return 0 }
        switch value {
        case let .double(number):
            return number
        case let .int64(number):
            return Double(number)
        case let .string(string):
            return Double(string) ?? 0
        case .null:
            return 0
        }
    }

}


private enum DemoSQLiteValue {
    case null
    case int64(Int64)
    case double(Double)
    case string(String)

    init(statement: OpaquePointer?, index: Int32) {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            self = .int64(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            self = .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            self = .string(String(cString: sqlite3_column_text(statement, index)))
        default:
            self = .null
        }
    }
}
