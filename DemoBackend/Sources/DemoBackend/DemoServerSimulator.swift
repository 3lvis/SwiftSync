import Foundation
import SQLite3

public enum DemoBackendError: LocalizedError {
    case openDatabase(String)
    case sqlite(message: String)
    case notFound(entity: String, id: String)
    case invalidReference(entity: String, id: String)

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
        }
    }
}

public final class DemoServerSimulator {
    private let sqlite: DemoSQLiteDatabase
    private let formatter = ISO8601DateFormatter()

    public init(databaseURL: URL, seedData: DemoSeedData) throws {
        self.sqlite = try DemoSQLiteDatabase(databaseURL: databaseURL)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try self.sqlite.execute("PRAGMA foreign_keys = ON;")
        try Self.createSchemaIfNeeded(sqlite: self.sqlite)
        try Self.seedIfNeeded(self.sqlite, seedData: seedData)
    }

    public func getProjectsPayload() throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT id, name, status, updated_at
            FROM projects
            ORDER BY id ASC
            """
        )
        return rows.map { row in
            [
                "id": row.string("id"),
                "name": row.string("name"),
                "status": row.string("status"),
                "updated_at": iso8601(row.double("updated_at"))
            ]
        }
    }

    public func getProjectTasksPayload(projectID: String) throws -> [[String: Any]] {
        try getTasksPayload(
            whereClause: "WHERE project_id = ?",
            bind: { stmt in self.sqlite.bind(text: projectID, at: 1, in: stmt) }
        )
    }

    public func getUsersPayload() throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT id, display_name, avatar_seed, role, updated_at
            FROM users
            ORDER BY id ASC
            """
        )
        return rows.map { row in
            [
                "id": row.string("id"),
                "display_name": row.string("display_name"),
                "avatar_seed": row.string("avatar_seed"),
                "role": row.string("role"),
                "updated_at": iso8601(row.double("updated_at"))
            ]
        }
    }

    public func getUserTasksPayload(userID: String) throws -> [[String: Any]] {
        try getTasksPayload(
            whereClause: "WHERE assignee_id = ?",
            bind: { stmt in self.sqlite.bind(text: userID, at: 1, in: stmt) }
        )
    }

    public func getTaskDetailPayload(taskID: String) throws -> [String: Any]? {
        let rows = try self.sqlite.query(
            """
            SELECT id, project_id, assignee_id, title, description, state, priority, due_date, updated_at
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

    public func getTaskCommentsPayload(taskID: String) throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT id, task_id, author_user_id, body, created_at, updated_at
            FROM comments
            WHERE task_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            bind: { stmt in
                self.sqlite.bind(text: taskID, at: 1, in: stmt)
            }
        )
        return rows.map { row in
            [
                "id": row.string("id"),
                "task_id": row.string("task_id"),
                "author_user_id": row.string("author_user_id"),
                "body": row.string("body"),
                "created_at": iso8601(row.double("created_at")),
                "updated_at": iso8601(row.double("updated_at"))
            ]
        }
    }

    public func getTagsPayload() throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT id, name, color_hex, updated_at
            FROM tags
            ORDER BY id ASC
            """
        )
        return rows.map { row in
            [
                "id": row.string("id"),
                "name": row.string("name"),
                "color_hex": row.string("color_hex"),
                "updated_at": iso8601(row.double("updated_at"))
            ]
        }
    }

    public func getTagTasksPayload(tagID: String) throws -> [[String: Any]] {
        try getTasksPayload(
            whereClause: """
            INNER JOIN task_tags ON task_tags.task_id = tasks.id
            WHERE task_tags.tag_id = ?
            """,
            bind: { stmt in
                self.sqlite.bind(text: tagID, at: 1, in: stmt)
            }
        )
    }

    @discardableResult
    public func patchTaskDescription(taskID: String, descriptionText: String) throws -> [String: Any]? {
        guard let current = try getTaskDetailPayload(taskID: taskID) else { return nil }
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

    public func createComment(taskID: String, authorUserID: String, body: String) throws -> [String: Any] {
        guard try exists(in: "tasks", id: taskID) else {
            throw DemoBackendError.invalidReference(entity: "task_id", id: taskID)
        }
        guard try exists(in: "users", id: authorUserID) else {
            throw DemoBackendError.invalidReference(entity: "author_user_id", id: authorUserID)
        }

        let now = nextTimestamp(after: nil)
        let newID = try nextCommentID()

        try self.sqlite.execute(
            """
            INSERT INTO comments (id, task_id, author_user_id, body, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            bind: { stmt in
                self.sqlite.bind(text: newID, at: 1, in: stmt)
                self.sqlite.bind(text: taskID, at: 2, in: stmt)
                self.sqlite.bind(text: authorUserID, at: 3, in: stmt)
                self.sqlite.bind(text: body, at: 4, in: stmt)
                self.sqlite.bind(double: now.timeIntervalSince1970, at: 5, in: stmt)
                self.sqlite.bind(double: now.timeIntervalSince1970, at: 6, in: stmt)
            }
        )

        let rows = try self.sqlite.query(
            """
            SELECT id, task_id, author_user_id, body, created_at, updated_at
            FROM comments
            WHERE id = ?
            LIMIT 1
            """,
            bind: { stmt in
                self.sqlite.bind(text: newID, at: 1, in: stmt)
            }
        )
        guard let row = rows.first else {
            throw DemoBackendError.notFound(entity: "comment", id: newID)
        }
        return [
            "id": row.string("id"),
            "task_id": row.string("task_id"),
            "author_user_id": row.string("author_user_id"),
            "body": row.string("body"),
            "created_at": iso8601(row.double("created_at")),
            "updated_at": iso8601(row.double("updated_at"))
        ]
    }

    private func getTasksPayload(
        whereClause: String,
        bind: ((OpaquePointer?) throws -> Void)?
    ) throws -> [[String: Any]] {
        let rows = try self.sqlite.query(
            """
            SELECT tasks.id, tasks.project_id, tasks.assignee_id, tasks.title, tasks.description, tasks.state,
                   tasks.priority, tasks.due_date, tasks.updated_at
            FROM tasks
            \(whereClause)
            ORDER BY tasks.id ASC
            """,
            bind: bind
        )
        return try rows.map(taskPayload(from:))
    }

    private func taskPayload(from row: DemoSQLiteRow) throws -> [String: Any] {
        let taskID = row.string("id")
        return [
            "id": taskID,
            "project_id": row.string("project_id"),
            "assignee_id": row.nullableString("assignee_id") ?? NSNull(),
            "title": row.string("title"),
            "description": row.string("description"),
            "state": row.string("state"),
            "priority": Int(row.int64("priority")),
            "due_date": row.nullableDouble("due_date").map(iso8601) ?? NSNull(),
            "tag_ids": try tagIDs(forTaskID: taskID),
            "updated_at": iso8601(row.double("updated_at"))
        ]
    }

    private func tagIDs(forTaskID taskID: String) throws -> [String] {
        let rows = try self.sqlite.query(
            """
            SELECT tag_id
            FROM task_tags
            WHERE task_id = ?
            ORDER BY tag_id ASC
            """,
            bind: { stmt in
                self.sqlite.bind(text: taskID, at: 1, in: stmt)
            }
        )
        return rows.map { $0.string("tag_id") }
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

    private func nextCommentID() throws -> String {
        let rows = try self.sqlite.query(
            """
            SELECT COALESCE(MAX(CAST(SUBSTR(id, 9) AS INTEGER)), 0) AS max_id
            FROM comments
            WHERE id LIKE 'comment-%'
            """
        )
        let next = Int(rows.first?.int64("max_id") ?? 0) + 1
        return "comment-\(next)"
    }

    private func parseISO8601(_ value: Any?) throws -> Date? {
        guard let string = value as? String else { return nil }
        if let date = formatter.date(from: string) {
            return date
        }
        throw DemoBackendError.sqlite(message: "Invalid ISO-8601 timestamp in payload: \(string)")
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

    private static func createSchemaIfNeeded(sqlite: DemoSQLiteDatabase) throws {
        try sqlite.executeScript(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                status TEXT NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                avatar_seed TEXT NOT NULL,
                role TEXT NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tags (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                assignee_id TEXT NULL,
                title TEXT NOT NULL,
                description TEXT NOT NULL,
                state TEXT NOT NULL,
                priority INTEGER NOT NULL,
                due_date REAL NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE RESTRICT,
                FOREIGN KEY(assignee_id) REFERENCES users(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS task_tags (
                task_id TEXT NOT NULL,
                tag_id TEXT NOT NULL,
                PRIMARY KEY (task_id, tag_id),
                FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS comments (
                id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                author_user_id TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
                FOREIGN KEY(author_user_id) REFERENCES users(id) ON DELETE RESTRICT
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
                    INSERT INTO projects (id, name, status, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: project.id, at: 1, in: stmt)
                        sqlite.bind(text: project.name, at: 2, in: stmt)
                        sqlite.bind(text: project.status, at: 3, in: stmt)
                        sqlite.bind(double: project.updatedAt.timeIntervalSince1970, at: 4, in: stmt)
                    }
                )
            }

            for user in seedData.users {
                try sqlite.execute(
                    """
                    INSERT INTO users (id, display_name, avatar_seed, role, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: user.id, at: 1, in: stmt)
                        sqlite.bind(text: user.displayName, at: 2, in: stmt)
                        sqlite.bind(text: user.avatarSeed, at: 3, in: stmt)
                        sqlite.bind(text: user.role, at: 4, in: stmt)
                        sqlite.bind(double: user.updatedAt.timeIntervalSince1970, at: 5, in: stmt)
                    }
                )
            }

            for tag in seedData.tags {
                try sqlite.execute(
                    """
                    INSERT INTO tags (id, name, color_hex, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: tag.id, at: 1, in: stmt)
                        sqlite.bind(text: tag.name, at: 2, in: stmt)
                        sqlite.bind(text: tag.colorHex, at: 3, in: stmt)
                        sqlite.bind(double: tag.updatedAt.timeIntervalSince1970, at: 4, in: stmt)
                    }
                )
            }

            for task in seedData.tasks {
                try sqlite.execute(
                    """
                    INSERT INTO tasks (id, project_id, assignee_id, title, description, state, priority, due_date, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: task.id, at: 1, in: stmt)
                        sqlite.bind(text: task.projectID, at: 2, in: stmt)
                        sqlite.bind(nullableText: task.assigneeID, at: 3, in: stmt)
                        sqlite.bind(text: task.title, at: 4, in: stmt)
                        sqlite.bind(text: task.descriptionText, at: 5, in: stmt)
                        sqlite.bind(text: task.state, at: 6, in: stmt)
                        sqlite.bind(int64: Int64(task.priority), at: 7, in: stmt)
                        sqlite.bind(nullableDouble: task.dueDate?.timeIntervalSince1970, at: 8, in: stmt)
                        sqlite.bind(double: task.updatedAt.timeIntervalSince1970, at: 9, in: stmt)
                    }
                )

                for tagID in task.tagIDs {
                    try sqlite.execute(
                        """
                        INSERT INTO task_tags (task_id, tag_id)
                        VALUES (?, ?)
                        """,
                        bind: { stmt in
                            sqlite.bind(text: task.id, at: 1, in: stmt)
                            sqlite.bind(text: tagID, at: 2, in: stmt)
                        }
                    )
                }
            }

            for comment in seedData.comments {
                try sqlite.execute(
                    """
                    INSERT INTO comments (id, task_id, author_user_id, body, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    bind: { stmt in
                        sqlite.bind(text: comment.id, at: 1, in: stmt)
                        sqlite.bind(text: comment.taskID, at: 2, in: stmt)
                        sqlite.bind(text: comment.authorUserID, at: 3, in: stmt)
                        sqlite.bind(text: comment.body, at: 4, in: stmt)
                        sqlite.bind(double: comment.createdAt.timeIntervalSince1970, at: 5, in: stmt)
                        sqlite.bind(double: comment.updatedAt.timeIntervalSince1970, at: 6, in: stmt)
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

    func bind(int64 value: Int64, at index: Int32, in stmt: OpaquePointer?) {
        sqlite3_bind_int64(stmt, index, value)
    }

    func bind(double value: Double, at index: Int32, in stmt: OpaquePointer?) {
        sqlite3_bind_double(stmt, index, value)
    }

    func bind(nullableDouble value: Double?, at index: Int32, in stmt: OpaquePointer?) {
        if let value {
            bind(double: value, at: index, in: stmt)
        } else {
            sqlite3_bind_null(stmt, index)
        }
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

    func nullableDouble(_ key: String) -> Double? {
        guard let value = values[key] else { return nil }
        switch value {
        case let .double(number):
            return number
        case let .int64(number):
            return Double(number)
        case let .string(string):
            return Double(string)
        case .null:
            return nil
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
