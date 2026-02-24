# SwiftSync Demo Model Hierarchy & Feature Map

This reference explains the SwiftData models used in the demo, traces their hierarchical relationships, and explicitly maps each **unique SwiftSync showcase** to a single model/relationship. The goal is to avoid duplicates: each feature (one-to-one, one-to-many, many-to-many, custom mapping, deep mapping) is illustrated by one definitive path, and any **ambiguous or redundant** relationship is noted so we can keep the demo focused.

## Model Hierarchy

- `Project` (`Demo/Demo/Models/DemoModels.swift:7-27`)
  - fields: `id`, `name`, `taskCount`, `updatedAt`
  - to-many: `tasks` → `Task`
- `Task` (`Demo/Demo/Models/DemoModels.swift:124-182`)
  - to-one: `project`, `assignee`, `reviewer`, `author`
  - optional scalars: `projectID`, `assigneeID`, `reviewerID`, `title`, `descriptionText`, `state`, `stateLabel`, `updatedAt`
  - scalars: `authorID`
  - to-many: `watchers`
  - remote keys show custom/deep mappings (`description`, `state.id`, `state.label`)
- `User` (`Demo/Demo/Models/DemoModels.swift:32-65`)
  - scalar `displayName`, `role`, `roleLabel`, `updatedAt`
  - inverse collections: `assignedTasks`, `reviewTasks`, `authoredTasks`, `watchedTasks`

## Feature Mapping (One feature per relationship)

### 1. One-to-one (Task → Assignee / Reviewer / Author)
- `Task.assignee`, `Task.reviewer`, and `Task.author` are to-one relationships wired to `User` (`Demo/Demo/Models/DemoModels.swift:133-145`).
- Backend schema/seed: `tasks.assignee_id`/`tasks.reviewer_id`/`tasks.author_id` with foreign keys (`DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift:939-951`, `1034-1050`), so SwiftSync demonstrates synced to-one updates and delete handling.
- **Single demo point:** assignee/reviewer edits on the task-detail screen show the to-one update path. Author exists to increase **ambiguity** (multiple valid `User` relationships) and to provide a stable “created by” anchor without adding another to-one feature.

### 2. One-to-many (Project → Tasks)
- `Project.tasks` collects all tasks for a project (`Demo/Demo/Models/DemoModels.swift:7-27`); each `Task` keeps a `project` back-reference (`Demo/Demo/Models/DemoModels.swift:142-148`).
- Schema enforces `tasks.project_id` and the corresponding server-side `getProjectTasksPayload` endpoint uses `WHERE project_id = ?` (`DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift:695-711`).
- The Projects list/detail flow is the sole demo surface that reads/writes parent-to-many slices, making this the dedicated one-to-many case.

### 3. Custom mapping (`descriptionText` for reserved key)
- `Task.descriptionText` carries `@RemoteKey("description")` to show how SwiftSync handles a backend field named `description`, which is otherwise reserved in Swift. This single property proves remapping for a reserved attribute while keeping the rest of `Task` unaffected (`Demo/Demo/Models/DemoModels.swift:132-137`).
- The backend keeps `description` as a column and uses it in `taskPayload` (`DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift:939-711`, `1034-1049`), so the demo exercises the remapping once when creating/updating tasks.

### 4. Options + Deep mapping (`state.label`)
- The demo uses **one** options-array surface: task state options (`[{"id","label"}]`) from `getTaskStateOptionsPayload`, and that same state drives the deep mapping (`state.id`, `state.label`) (`Demo/Demo/Models/DemoModels.swift:137-140`, `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift:695-729`).
- This is the only options showcase and the only deep mapping showcase; no other model should add option arrays or nested label mappings.

## Ambiguous/Redundant Cases (avoid duplicates)

- `Task.watchers` ↔ `User.watchedTasks` is a many-to-many link backed by `task_watchers`. We keep it primarily to demonstrate **explicit `through:` usage** on ambiguous `relatedTo` queries involving `User`.
- The inverse to-many collections on `User` (`assignedTasks`, `reviewTasks`, `authoredTasks`, `watchedTasks`) rely on the same `tasks.*_id` columns already used for the to-one and many-to-many features, so they are not separate SwiftSync demos; they surface as part of the task-detail interactions instead.

## Summary

| Feature | Model / Relationship | Backend point of truth | Notes |
| --- | --- | --- | --- |
| One-to-one | `Task.assignee` / `Task.reviewer` / `Task.author` | `tasks.assignee_id` / `tasks.reviewer_id` / `tasks.author_id` | Single write/read path for to-one updates + ambiguity |
| One-to-many | `Project.tasks` | `tasks.project_id` + `getProjectTasksPayload` | Dedicated parent slice sync |
| Custom Mapping | `Task.descriptionText` `@RemoteKey("description")` | `tasks.description` | Reserved-key mapping demo |
| Deep Mapping | `Task.state` + `Task.stateLabel` | `taskStatePayload` | Structured `state` payload ensures `state.label` path is exercised |

Keep this document in sync with the Demo models/back-end whenever we decide to add or remove a model so the “one unique demo per feature” principle stays true.
