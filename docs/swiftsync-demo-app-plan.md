# SwiftSync Demo App Plan (SwiftUI, Staged Sync, Three-Phase Rollout)

## Goal

Build a demo app that proves SwiftSync can deliver:

1. Reactive SwiftUI reads via `@SyncQuery` and `@SyncModel`.
2. Multi-step backend loading (not a single giant JSON payload).
3. Predictable sync behavior with simulated latency/failures.
4. A phased path from read-only to editable to offline-first sync.

## Scope

- Platform/UI: iOS + SwiftUI.
- Data stack: SwiftData + SwiftSync.
- Networking: fake backend service (in-process, deterministic delays/errors).
- App shell: two tabs only.
  - `Projects`
  - `Users`
- Workspace setup: Xcode workspace containing:
  - `SwiftSync` package
  - `SwiftSyncDemo` app target

## Demo Domain

This demo intentionally highlights multiple relationship types.

- `Project` -> to-many `Task`
- `Task` -> to-one `User` (`assignee`)
- `User` -> to-many `Task` (inverse)
- `Task` <-> to-many `Tag` (many-to-many)
- `Task` -> to-many `Comment`

## Data Model (SwiftData + Syncable)

### `Project`

- `id: String` (`@PrimaryKey`)
- `name: String`
- `status: String`
- `serverUpdatedAt: Date`
- relationship: `tasks: [Task]`

### `User`

- `id: String` (`@PrimaryKey`)
- `displayName: String`
- `avatarSeed: String`
- `role: String`
- `serverUpdatedAt: Date`
- inverse relationship: `assignedTasks: [Task]`

### `Task`

- `id: String` (`@PrimaryKey`)
- `projectID: String`
- `assigneeID: String?`
- `title: String`
- `descriptionText: String`
- `state: String` (`todo`, `inProgress`, `done`)
- `priority: Int`
- `dueDate: Date?`
- `serverUpdatedAt: Date`
- relationships:
  - `project: Project?`
  - `assignee: User?`
  - `tags: [Tag]`
  - `comments: [Comment]`

### `Tag`

- `id: String` (`@PrimaryKey`)
- `name: String` (e.g. `frontend`)
- `colorHex: String`
- `serverUpdatedAt: Date`
- inverse relationship: `tasks: [Task]`

### `Comment`

- `id: String` (`@PrimaryKey`)
- `taskID: String`
- `authorUserID: String`
- `body: String`
- `createdAt: Date`
- `serverUpdatedAt: Date`
- relationships:
  - `task: Task?`
  - `author: User?`

## Fake Backend Contract

### Endpoints (Staged Fetches)

1. `GET /projects`
2. `GET /projects/{projectID}/tasks` (summary task payload; no full description body updates unless changed)
3. `GET /users`
4. `GET /users/{userID}/tasks` (for Users tab drill-in)
5. `GET /tasks/{taskID}` (full task detail, includes description)
6. `GET /tasks/{taskID}/comments`
7. `GET /tags`
8. `GET /tags/{tagID}/tasks`

### Write Endpoints

1. `PATCH /tasks/{taskID}` (title/state/assignee/priority)
2. `PATCH /tasks/{taskID}/description` (from modal edit flow)
3. `PUT /tasks/{taskID}/tags` (full set replace or additive/removal contract)
4. `POST /tasks/{taskID}/comments`

### Backend Simulation Behavior

- Delay per endpoint (`200ms` to `1500ms`, jittered).
- Optional transient failures (debug-configurable rates).
- Deterministic scenario presets:
  - `fastStable`
  - `slowNetwork`
  - `flakyNetwork`
  - `offline`
- Conflict simulation via `serverUpdatedAt` and optional `version` field.
- Large seeded dataset for realistic list stress:
  - 30+ projects
  - 300+ tasks
  - 40+ users
  - 50+ tags
  - 2,000+ comments

## App Architecture

### Layers

1. `DemoAPIClient` protocol + `FakeDemoAPIClient` implementation.
2. `SyncEngine` service that maps DTOs into SwiftSync `sync(...)` calls.
3. `SyncContainer` as single data entry point.
4. SwiftUI features reading through `@SyncQuery` / `@SyncModel`.

### Suggested Modules/Groups

- `SwiftSyncDemo/App`
- `SwiftSyncDemo/Models`
- `SwiftSyncDemo/Networking`
- `SwiftSyncDemo/Sync`
- `SwiftSyncDemo/Features/Projects`
- `SwiftSyncDemo/Features/Users`
- `SwiftSyncDemo/Features/TaskDetail`
- `SwiftSyncDemo/Features/Tags`
- `SwiftSyncDemo/Offline` (phase 3)

## SwiftUI Feature Flows

### Tab 1: Projects

- Projects list via `@SyncQuery(Project.self, in: syncContainer, sortBy: [\.name, \.id])`.
- On first appearance: trigger `syncProjects()`.
- Project detail:
  - Header via `@SyncModel(Project.self, id: projectID, in: syncContainer)`.
  - Task list via `@SyncQuery(Task.self, predicate: #Predicate { $0.projectID == projectID }, in: syncContainer, sortBy: [SortDescriptor(\Task.priority, order: .reverse), SortDescriptor(\Task.id)])`.
  - On first appearance: trigger `syncProjectTasks(projectID:)`.

### Tab 2: Users

- Users list via `@SyncQuery(User.self, in: syncContainer, sortBy: [\.displayName, \.id])`.
- On first appearance: trigger `syncUsers()`.
- User detail task list via assignee filter:
  - `@SyncQuery(Task.self, predicate: #Predicate { $0.assigneeID == userID }, in: syncContainer, sortBy: [SortDescriptor(\Task.priority, order: .reverse), SortDescriptor(\Task.id)])`.
- Optionally trigger `syncUserTasks(userID:)` when entering screen.

### Task Detail

- Task core model via `@SyncModel(Task.self, id: taskID, in: syncContainer)`.
- Assignee display via task relation or `@SyncModel(User.self, id: assigneeID, in: syncContainer)`.
- Tag chips from task-tag relation.
- Comments list via `@SyncQuery(Comment.self, predicate: #Predicate { $0.taskID == taskID }, in: syncContainer, sortBy: [SortDescriptor(\Comment.createdAt, order: .reverse), SortDescriptor(\Comment.id)])`.
- On first appearance:
  - `syncTaskDetail(taskID:)`
  - `syncTaskComments(taskID:)`.

### Description Editing Rule

- In task detail, description is read-only.
- Edit action opens modal sheet (`EditTaskDescriptionView`).
- Save action goes through sync pipeline (`PATCH /tasks/{taskID}/description`).
- Close modal and let reactive wrappers refresh visible task detail state.

### Tag Drill-In Flow

- From task detail, tap tag chip `#frontend`.
- Navigate to `TagTasksView(tagID:)`.
- Screen uses:
  - `@SyncModel(Tag.self, id: tagID, in: syncContainer)`.
  - `@SyncQuery(Task.self, ... by tag relation ...)`.
- On first appearance: trigger `syncTagTasks(tagID:)`.

## Relationship Types Demonstrated

1. One-to-many: `Project -> [Task]`.
2. Many-to-one: `Task -> User (assignee)`.
3. One-to-many inverse: `User -> [Task]`.
4. Many-to-many: `Task <-> [Tag]`.
5. Nested one-to-many: `Task -> [Comment]`.

## Phase 1: Read-Only, Mocked Data, Staged Fetching

### Behavior

1. App launch:
   - Show local cache immediately via `@SyncQuery`.
   - Trigger `syncProjects()` and `syncUsers()`.
2. Enter project:
   - Show cached tasks instantly.
   - Trigger `syncProjectTasks(projectID:)`.
3. Enter task detail:
   - Show cached detail/comments instantly.
   - Trigger detail/comments sync calls.
4. Enter tag drill-in:
   - Show cached related tasks.
   - Trigger `syncTagTasks(tagID:)`.

### Key Objective

Demonstrate relationship traversal and staged fetch behavior using a large fake dataset, with no write paths.

### Phase 1 Constraints

- All screens are read-only.
- No create/edit/delete UI in this phase.
- Data source is fake backend only (plus local cache of synced data).

## Phase 2: Editable Online Flows

### Requirements

1. Add create/edit capabilities while online.
2. Support creating:
   - project
   - task
   - comment
   - user
3. Continue using staged sync and reactive wrappers as primary read path.
4. Preserve modal-only task description editing rule.

### Write Endpoints Used in Phase 2

1. `POST /projects`
2. `POST /tasks`
3. `POST /users`
4. `POST /tasks/{taskID}/comments`
5. `PATCH /tasks/{taskID}`
6. `PATCH /tasks/{taskID}/description`
7. `PUT /tasks/{taskID}/tags`

### Key Objective

Demonstrate that create/edit operations flow through SwiftSync and refresh affected screens without manual reload plumbing.

## Phase 3: Offline-First + Reconnect Replay

### Requirements

1. If app opens offline, render local data immediately.
2. Offline create/edit operations are persisted locally and queued.
3. On reconnect, queued operations replay in order.
4. UI remains responsive while replay runs.

### Additional Components

- `NetworkMonitor` abstraction (`online`/`offline`).
- `OutboxOperation` SwiftData model:
  - `id`, `kind`, `entityID`, `payload`, `createdAt`, `retryCount`, `lastError`.
- `OutboxProcessor` with:
  - ordered replay
  - exponential backoff for transient failures
  - failure surfacing after retry threshold.

### Offline Write Examples

1. Create a project.
2. Create a task.
3. Create a comment.
4. Create a user.
5. Reassign task assignee.
6. Change task description from modal.
7. Add/remove tags on a task.

All operations should update local UI immediately and queue network writes.

### Conflict Policy (Demo Default)

- Default: `serverWins` for simplicity.
- Optional debug toggle: `clientLastWriteWins`.

### Read Policy

- Always read from local store (`@SyncQuery` / `@SyncModel`).
- Connectivity affects sync activity only, not rendering source.

## UX States to Demonstrate

- `Offline`/`Online` banner.
- `Pending changes: N` global indicator.
- Per-task pending marker when offline edits exist.
- `Last synced` timestamp in project/user/task screens.

## Demo Scenario Script

1. Launch online with empty DB.
2. Phase 1 walkthrough: browse projects/users/tasks/comments/tags with staged fetches.
3. Phase 2 walkthrough: create project, task, user, and comment while online.
4. Validate reactive updates across affected screens.
5. Go offline and perform create/edit operations.
6. Observe immediate local UI updates + pending indicators.
7. Reconnect and observe automatic replay/clear.
8. Inject conflict and observe selected conflict policy.

## Testing Plan

### Unit Tests

- DTO -> model mapping for all endpoints.
- Relationship mapping correctness:
  - project-task
  - task-assignee
  - task-tag many-to-many
  - task-comment
- Slice sync isolation:
  - project sync does not clobber unrelated task detail/comment fields.
  - tag sync updates membership correctly.
- Phase 2 write mapping tests:
  - create project/task/user/comment request/response mapping.
- Outbox ordering/retry logic.

### Integration Tests

- Phase 1:
  - seeded data renders correctly with staged fetches.
- Phase 2:
  - create flows update UI via reactive wrappers without manual reload.
- Phase 3:
  - launch offline with seeded data renders instantly.
- Offline edits survive app restart.
- Reconnect drains outbox and converges local state.
- `@SyncQuery`/`@SyncModel`-backed screens update after background sync without manual reload.

## Acceptance Criteria

1. Two-tab app (`Projects`, `Users`) is fully functional.
2. All major relationship types are visible in user flows.
3. Phase 1 is read-only and uses large fake backend content.
4. Phase 2 supports creating project/task/comment/user.
5. Task description remains editable only through modal flow.
6. Tag drill-in correctly shows tasks for selected tag.
7. Phase 3 offline edits replay automatically on reconnect.
8. Reactive wrappers are primary read APIs throughout UI.

## Implementation Milestones

1. Workspace + app target + package wiring.
2. Models + fake backend + large seeded fixtures + scenario switcher.
3. Phase 1 read-only screens and staged sync calls.
4. Phase 2 create/edit flows.
5. Phase 3 outbox + network monitor + replay.
6. Test suite + debug panel for network/conflict simulation.

## Nice-to-Have Enhancements

- Event timeline view for sync invalidations.
- Seed sizes (`small`, `medium`, `large`) for stressing list updates.
- In-app “scripted demo mode” that walks through scenarios automatically.
