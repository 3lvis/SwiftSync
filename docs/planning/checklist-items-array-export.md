# Checklist Items — Inline Relationship Export Demo

## Goal

Add a `ChecklistItem` model to the demo that demonstrates inline relationship export
in a genuine, useful way: checklist items are sent inline with the task body on both
create and update, in one atomic request. No separate follow-up endpoint.

This is the first honest end-to-end use of relationship export in the demo. It replaces
the current bare `exportObject(for:)` call in `TaskFormSheet.save()` — which previously
used `relationshipMode: .none` (now removed) — and shows relationships being sent inline
at a real call site.

---

## Why Checklist Items

The existing demo shows reviewers and watchers as separate replace-endpoint calls
(`PUT /tasks/{id}/reviewers`, `PUT /tasks/{id}/watchers`). That pattern exists because
the server treats membership as a join table, not as a child-object graph.

Checklist items are structurally different: they are owned by exactly one task, have
no independent identity outside that task, and the whole set is replaced atomically
whenever the task is updated. That is the precise use case `.array` is designed for —
"send the parent and all its children in one request, let the server own the transaction."

A task management app without checklists is also a natural omission. The feature earns
its place on its own merits.

---

## Current State

One call site uses `exportObject` in the entire demo:

```swift
// TaskFormSheet.swift:340
let body = draft.exportObject(for: syncContainer)
```

Relationships on `Task` (`reviewers`, `watchers`, `project`, `author`, `assignee`) will
be exported inline as child objects unless marked `@NotExport`. Currently they are not
marked, so they would appear in the body — but the server ignores them (it reads only
scalar FKs). Checklist items do not exist yet.

The server (`DemoServerSimulator`) has no `checklist_items` table and no concept of
inline child objects in any endpoint body.

---

## Decisions

- **Toggle done/undone in detail view triggers an immediate save.** Tapping a checkbox
  calls `updateTask` with the full updated item list inline. This exercises the update
  path with `.array`, not just create.

- **Drag-to-reorder in the task form.** Items have a `position` integer field.
  Reordering in the form updates positions before export. The server stores and returns
  items ordered by `position`.

- **Checklist count badge on task list rows.** `ProjectDetailView` task rows show a
  `done/total` count (e.g. `2 / 5`). Requires `refreshOn: [\.checklistItems]` on the
  `@SyncQuery` so the list re-renders when item state changes.

- **Inline in the task payload (embedded, not a separate endpoint).** The server embeds
  `checklist_items: [{...}]` in every task response. No `GET /tasks/{id}/checklist-items`
  endpoint. The existing `syncTaskDetail` + `syncProjectTasks` calls already re-fetch
  the full task payload; `ChecklistItem` rows are synced automatically as nested objects
  within that payload using `syncContainer.sync(item:as:)` on the task.

- **`.array` replaces `.none` at the export call site.** Both create and update use
  `.array`. Reviewers and watchers continue to use their dedicated replace endpoints
  (they are join-table relationships, not owned children).

---

## Wire Format

### What inline export produces for `checklistItems`

`@Syncable` generates an export block for every relationship not marked `@NotExport`.
`Task.checklistItems` exports as:

```json
{
  "id": "task-1",
  "title": "Buy milk",
  "description": "...",
  "state": { "id": "todo", "label": "To Do" },
  "checklist_items": [
    { "id": "item-a", "title": "Oat milk", "done": false, "position": 0, "created_at": "...", "updated_at": "..." },
    { "id": "item-b", "title": "Almond milk", "done": true,  "position": 1, "created_at": "...", "updated_at": "..." }
  ]
}
```

The key is `checklist_items` (snake_case of `checklistItems`). The value is a plain
JSON array of child objects — not ID strings, not an indexed dict. This is what
`.array` mode produces, and what the server reads.

### What the server returns (task payload with embedded items)

```json
{
  "id": "task-1",
  "title": "Buy milk",
  "description": "...",
  "state": { "id": "todo", "label": "To Do" },
  "project_id": "proj-1",
  "assignee_id": null,
  "reviewer_ids": [],
  "watcher_ids": [],
  "author_id": "user-1",
  "created_at": "...",
  "updated_at": "...",
  "checklist_items": [
    { "id": "item-a", "task_id": "task-1", "title": "Oat milk",    "done": false, "position": 0, "created_at": "...", "updated_at": "..." },
    { "id": "item-b", "task_id": "task-1", "title": "Almond milk", "done": true,  "position": 1, "created_at": "...", "updated_at": "..." }
  ]
}
```

### Key for absent `checklist_items` on update

Standard absent-key-means-preserve semantics apply. If `checklist_items` is absent from
the PUT body, the server leaves the existing items untouched. If the key is present (even
as an empty array `[]`), the server deletes all existing items and inserts the new set.

This matches the same contract that `assignee_id` already uses in `updateTask`:
present-key-means-replace, absent-key-means-preserve.

---

## Server Changes (`DemoServerSimulator.swift`)

### 1. New `checklist_items` table (DDL, `createSchemaIfNeeded`)

```sql
CREATE TABLE IF NOT EXISTS checklist_items (
    id         TEXT    PRIMARY KEY,
    task_id    TEXT    NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    title      TEXT    NOT NULL,
    done       INTEGER NOT NULL DEFAULT 0,
    position   INTEGER NOT NULL DEFAULT 0,
    created_at REAL    NOT NULL,
    updated_at REAL    NOT NULL
);
```

`ON DELETE CASCADE` ensures items are deleted when their task is deleted. No separate
cleanup needed.

### 2. New helper `checklistItemsPayload(taskID:) -> [[String: Any]]`

Analogous to `reviewerIDsFor(taskID:)`. Queries `checklist_items` ordered by `position ASC, id ASC`
and returns each row as a dict: `id`, `task_id`, `title`, `done` (Bool), `position` (Int),
`created_at`, `updated_at`.

```swift
private func checklistItemsPayload(taskID: String) throws -> [[String: Any]] {
    let rows = try sqlite.query(
        "SELECT * FROM checklist_items WHERE task_id = ? ORDER BY position ASC, id ASC",
        bind: { stmt in sqlite.bind(text: taskID, at: 1, in: stmt) }
    )
    return rows.map { row in [
        "id":         row.string("id"),
        "task_id":    row.string("task_id"),
        "title":      row.string("title"),
        "done":       row.int64("done") != 0,
        "position":   Int(row.int64("position")),
        "created_at": iso8601(row.double("created_at")),
        "updated_at": iso8601(row.double("updated_at"))
    ]}
}
```

### 3. Extend `taskPayload(from:)` — embed items in every task response

Add `"checklist_items": try checklistItemsPayload(taskID: taskID)` to the dict returned
by `taskPayload(from:)`. Every task response — list and detail — now includes the full
item array. No separate endpoint needed.

### 4. Extend `createTask(body:)` / `createTaskInternal`

After the task `INSERT`, check for `body["checklist_items"]` as `[[String: Any]]`.
If present and non-empty, insert each item in the same transaction as the task.

The entire create (task + items) must run inside `BEGIN TRANSACTION / COMMIT`. The
current `createTaskInternal` does not use an explicit transaction (it relies on SQLite's
implicit per-statement transactions). Wrap it.

Required item fields: `id` (String), `title` (String).
Optional: `done` (Bool, default `false`), `position` (Int, default loop index).
Item IDs must be unique within `checklist_items`. Validate non-empty title.

### 5. Extend `updateTask(body:)` — replace items when key is present

After the task `UPDATE`, check `body.keys.contains("checklist_items")`:
- **Key present:** `DELETE FROM checklist_items WHERE task_id = ?`, then INSERT each
  item from the array. Wrap the update + delete + inserts in a single transaction.
- **Key absent:** leave items untouched.

This matches the absent-key-means-preserve contract used for `assignee_id`.

---

## Client Model Changes (`DemoModels.swift`)

### New `ChecklistItem` model

```swift
@Syncable
@Model
final class ChecklistItem {
    @Attribute(.unique) var id: String
    var title: String
    var done: Bool
    var position: Int
    var createdAt: Date
    var updatedAt: Date
    var task: Task?

    init(
        id: String = UUID().uuidString,
        title: String = "",
        done: Bool = false,
        position: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        task: Task? = nil
    ) { ... }
}
```

`@Syncable` generates `apply(_:)` and `exportObject(using:)` for free. The `task`
to-one back-reference is how SwiftSync's parent-scoped sync resolves the relationship.

### Extend `Task`

```swift
@Relationship(deleteRule: .cascade, inverse: \ChecklistItem.task)
var checklistItems: [ChecklistItem]
```

`deleteRule: .cascade` mirrors the server's `ON DELETE CASCADE`. The explicit
`inverse:` anchor is required — without it, SwiftData creates two separate join tables
for a many-to-many that isn't one. (See `docs/project/relationship-integrity.md`.)

Add `checklistItems: [ChecklistItem] = []` to `Task.init`.

### Register `ChecklistItem` in the schema

Wherever `SyncContainer` is initialised with the model schema, add `ChecklistItem.self`
to the type list.

---

## Sync — How Items Are Synced

No new sync method is needed. The server now embeds `checklist_items` in every task
response. `SyncContainer` can sync nested child objects within a parent payload using
parent-scoped sync.

`syncTaskDetailInternal` currently calls:

```swift
try await syncContainer.sync(item: payload, as: Task.self)
```

This syncs the `Task` row from the flat scalar fields. The embedded `checklist_items`
array in `payload` is not yet consumed — SwiftSync does not automatically recurse into
embedded arrays unless the caller explicitly syncs the nested payload.

The sync call needs to be extended to also sync the nested items:

```swift
let taskPayload = try await apiClient.getTaskDetail(taskID: taskID)
try await syncContainer.sync(item: taskPayload, as: Task.self)

if let items = taskPayload["checklist_items"] as? [[String: Any]],
   let task = try syncContainer.mainContext.fetch(FetchDescriptor<Task>()).first(where: { $0.id == taskID }) {
    try await syncContainer.sync(payload: items, as: ChecklistItem.self, parent: task)
}
```

The same pattern applies in `syncProjectTasksInternal` for list-level syncs: after
syncing tasks, iterate the returned task payloads and sync embedded `checklist_items`
for each.

This is slightly verbose. If the volume of tasks-per-project is large, syncing
checklist items for all tasks in a list sync may be more than needed. An acceptable
tradeoff for the demo: sync items only in `syncTaskDetailInternal` (detail-level),
not in `syncProjectTasksInternal` (list-level). The list view only shows a count badge;
it gets the count from the local store after detail syncs populate it. The detail view
always does its own sync.

**Open question:** Whether to also sync items in list-level syncs depends on whether
the count badge needs to be accurate for tasks the user has never opened. For the demo,
accuracy after a detail visit is sufficient.

---

## Export Call Site Change (`TaskFormSheet.swift`)

`exportObject(for:)` now always includes relationships unless `@NotExport` is applied.
The call site already uses the right form:

```swift
let body = draft.exportObject(for: syncContainer)
```

With `checklistItems` added to `Task` (and not marked `@NotExport`), the generated
export code emits `checklist_items: [{...}]` inline. Reviewers and watchers are also
relationships — they will appear in the body as `reviewers: [{id, display_name, ...}]`
and `watchers: [{...}]`.

**This is a problem.** The server's `createTask` and `updateTask` do not read `reviewers`
or `watchers` from the body (they use dedicated endpoints). Sending them inline is
harmless (the server ignores unknown keys), but it bloats the body unnecessarily with
full user objects for every reviewer and watcher.

Two options:

**Option A — Use `@NotExport` on `reviewers` and `watchers` in `Task`.**
`@NotExport` tells the macro to exclude the property from the generated export block.
Clean, compile-time guarantee that those fields never appear in any export of `Task`.
Downside: permanent exclusion — if a future endpoint wants reviewers inline, `@NotExport`
must be removed.

**Option B — Strip the keys from the body dict after export.**
After calling `exportObject`, manually remove `"reviewers"` and `"watchers"` from the
returned dict before passing it to the API client. Explicit and reversible, but
requires knowing the key names at the call site.

**Recommendation: Option A (`@NotExport`).**
The demo has no current or planned inline-reviewer endpoint. The intent of the separate
replace endpoint is clear. `@NotExport` documents this intent at the model level and
also demonstrates the `@NotExport` macro in a realistic context — it currently has no
demo usage.

Add to `Task` in `DemoModels.swift`:

```swift
@NotExport @Relationship var reviewers: [User]
@NotExport @Relationship var watchers: [User]
```

This also demonstrates `@NotExport` in a real model — a second payoff from this change.

Similarly, `project: Project?`, `author: User?`, and `assignee: User?` are to-one
relationships that export as full objects under `.array`. `project` and `author` are
immutable server-side — sending them inline on update is wasteful. `assignee` is sent
as `assignee_id` (the scalar FK), not as an inline object.

Mark those with `@NotExport` too:

```swift
@NotExport var project: Project?
@NotExport var author: User?
@NotExport var assignee: User?
```

With these in place, the exported body contains exactly what the server reads:
scalars (`id`, `title`, `description`, `state`, `assignee_id`, timestamps) plus
`checklist_items: [{...}]`.

---

## Toggle on Detail View (`TaskDetailView.swift`)

The task detail adds a "Checklist" section. Each item row has a checkbox button and the
item title. Tapping the checkbox:

1. Updates `item.done` on the local `ChecklistItem` object (optimistic UI)
2. Calls `syncEngine.updateTask(taskID:projectID:body:)` with the full updated task body

The body is built by re-exporting the task:

```swift
func toggleChecklistItem(_ item: ChecklistItem, task: Task) {
    item.done.toggle()
    item.updatedAt = Date()
    task.updatedAt = Date()
    let body = task.exportObject(for: syncContainer)
    _Concurrency.Task {
        try? await syncEngine.updateTask(taskID: task.id, projectID: task.projectID, body: body)
    }
}
```

The optimistic local write happens before the network call. If the call fails, the UI
shows an error but the local state is not rolled back (same pattern used elsewhere in
the demo). The next `syncTaskDetail` poll will reconcile.

`TaskDetailView` currently uses `@SyncModel` for the task, which is a live reactive
read. The `ChecklistItem` objects are accessed via `taskModel.checklistItems`. Because
`checklistItems` is a SwiftData relationship, changes to `ChecklistItem` rows (from the
post-update sync) will propagate through the existing reactive machinery without any
additional query setup in `TaskDetailView`.

---

## Count Badge on Task List (`ProjectDetailView` in `ProjectsTabView.swift`)

The task row label in `ProjectDetailView` currently shows title + state + assignee.
Add a checklist count badge: `{done} / {total}`, hidden when `checklistItems` is empty.

```swift
let items = task.checklistItems
if !items.isEmpty {
    let done = items.filter(\.done).count
    Text("\(done) / \(items.count)")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

The `@SyncQuery` for tasks in `ProjectDetailView` currently has `refreshOn: [\.assignee]`.
Add `\.checklistItems` to the `refreshOn` list so the query re-fires when checklist
items change:

```swift
_tasks = SyncQuery(
    Task.self,
    relatedTo: Project.self,
    relatedID: projectID,
    in: syncContainer,
    sortBy: [...],
    refreshOn: [\.assignee, \.checklistItems],
    animation: .snappy(duration: 0.24)
)
```

This ensures the badge updates immediately after a toggle, without waiting for the
polling loop.

---

## Task Form UI (`TaskFormSheet.swift`)

A "Checklist" `Section` appears below the description field in the form. It contains:

- A text field row with placeholder "Add item…" and an "Add" button (or return-key
  action) that appends a new `ChecklistItem` to `draft.checklistItems`
- A `ForEach` over `draft.checklistItems` sorted by `position`, with `.onMove` support
  for drag-to-reorder
- Each item row: drag handle (implicit from `editMode`), title text field, delete button

On reorder, update `position` on affected items to match the new indices before export.

Items are inserted into the same throwaway `editContext` that `draft` lives in, so
relationship assignment is safe (no cross-context issues).

**Create mode:** new items are attached to `draft` before `exportObject` is called.
The exported body includes the items inline. No post-create follow-up call for items.

**Edit mode:** the throwaway `editContext` fetches the existing task (and its items via
the relationship) into the isolated context. The user adds/removes/reorders items.
On save, `exportObject` includes the full updated item list. The server replaces all
items atomically.

---

## Sync Engine Changes (`DemoSyncEngine.swift`)

No new public methods. Two internal changes:

**`syncTaskDetailInternal`** — after syncing the task, sync embedded items:

```swift
private func syncTaskDetailInternal(taskID: String) async throws {
    guard let payload = try await apiClient.getTaskDetail(taskID: taskID) else { return }
    try await syncContainer.sync(item: payload, as: Task.self)
    if let items = payload["checklist_items"] as? [[String: Any]] {
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID })
        if let task = try syncContainer.mainContext.fetch(descriptor).first {
            try await syncContainer.sync(payload: items, as: ChecklistItem.self, parent: task)
        }
    }
}
```

**`syncProjectTasksInternal`** — optionally sync items for each task in the list
response. See the open question in the Sync section above. For the initial implementation,
skip list-level item sync and only sync on detail. Revisit if the badge is stale too often.

---

## Files to Touch

| File | Change |
|---|---|
| `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift` | New DDL, `checklistItemsPayload`, extend `taskPayload`, extend `createTask`/`updateTask` with transaction and item insert/replace |
| `Demo/Demo/Models/DemoModels.swift` | New `ChecklistItem` model; extend `Task` with `checklistItems` relationship and `@NotExport` on `reviewers`, `watchers`, `project`, `author`, `assignee` |
| `Demo/Demo/App/DemoRuntime.swift` | Register `ChecklistItem.self` in the schema |
| `Demo/Demo/Sync/DemoSyncEngine.swift` | Extend `syncTaskDetailInternal` to sync embedded items |
| `Demo/Demo/Features/TaskFormSheet.swift` | Checklist section UI; `exportObject(for:)` already correct — `@NotExport` on unwanted relationships |
| `Demo/Demo/Features/TaskDetail/TaskDetailView.swift` | Checklist section with toggle; `toggleChecklistItem` helper |
| `Demo/Demo/Features/Projects/ProjectsTabView.swift` | Count badge on task rows; add `\.checklistItems` to `refreshOn` |

No library (`Sources/SwiftSync/`) changes required.

---

## Open Questions

1. **List-level item sync.** Should `syncProjectTasksInternal` also sync `checklist_items`
   from each task payload, or only `syncTaskDetailInternal`? List-level sync would keep
   badges accurate even for tasks the user has never opened, but adds N sync calls per
   list refresh (one per task). For the demo, detail-only is sufficient. Revisit if the
   badge feels stale.

2. **`@NotExport` on `assignee` vs `assignee_id`.** The server reads `assignee_id`
   (the scalar FK). `assignee: User?` (the relationship) exports under `.array` as a
   full user object under the key `assignee`. The server ignores unknown keys, so this
   is harmless, but wastes bytes. Marking `assignee` with `@NotExport` while keeping
   `assigneeID` exported is correct. Confirm this is the intended split before
   implementation.

3. **Ambient mutations and checklist items.** `DemoServerSimulator` runs background
   ambient mutations on projects (create/update/delete tasks). These do not create
   checklist items. Ambient-mutated tasks will show an empty checklist, which is fine.
   No change needed.

4. **Seed data.** Should the initial seed tasks include checklist items? Adding a few
   seeded items would make the feature immediately visible on first launch without
   requiring the user to create a task first. Recommended: yes, seed 2–3 items on one
   existing task per project.

---

## Status

Planned. Not yet implemented.
