# SwiftSync Demo App Plan (SwiftUI, Staged Sync, Stateful Fake Backend)

## Status Legend

- `[X]` done (implemented in current demo)
- `[ ]` not done yet
- `[-]` partially done / foundation exists but feature is incomplete

## Current Status (2026-02-22)

### What is done now

- [X] Demo app target exists and builds
- [X] Single primary shell (`Projects`) with drill-in screens
- [X] Fake backend with staged read endpoints
- [X] Scenario presets (`fastStable`, `slowNetwork`, `flakyNetwork`, `offline`)
- [X] Curated seeded story dataset (3 projects / 6 users / 12 tags / 12 tasks / 20 comments)
- [X] Reactive reads use `@SyncQuery` / `@SyncModel`
- [X] Project -> tasks flow
- [X] Task detail with tags + comments
- [X] Tag drill-in -> tasks
- [X] Staged sync via `DemoSyncEngine`
- [X] Read-only Phase 1 behavior (core path)
- [X] Backend work split into separate plan (`docs/planning/swiftsync-demo-backend-plan.md`)

### What is still missing

- [ ] Offline/replay work (intentionally deferred until backend + writes are working)
- [ ] Demo-specific test coverage planned in this document

## Related Planning Document (Backend Work)

Backend implementation planning now lives in:

- `docs/planning/swiftsync-demo-backend-plan.md`
- `docs/planning/swiftsync-demo-crud-flows-plan.md`
- `docs/planning/swiftsync-demo-field-reduction-plan.md`

This demo app plan tracks UI flows, sync-engine integration, and staged feature rollout. The backend plan tracks SQLite storage, fake backend endpoint behavior, and backend unit tests.

## Demo Purpose

Build a focused demo that proves the main SwiftSync behaviors with as little UI/domain complexity as possible.

The demo is not a mini product. It is a showcase for:

- relationship syncing (`toOne`, `toMany`, parent-scoped sync)
- staged reads and targeted refresh
- backend-authoritative writes followed by sync-based UI refresh
- realistic payload shapes (attributes, foreign keys, arrays of IDs)
- failure scenarios (`slow`, `flaky`, `offline`) without changing app architecture

## Demo Mantra

- Prove SwiftSync, not product breadth.
- Keep support data seeded unless CRUD adds new sync behavior.
- Make writes go to the backend first, then refresh through SwiftSync reads.
- Prefer one strong example per concept over multiple redundant screens.

## Core Showcase (What Must Be Demonstrated)

- [X] One-to-many: `Project -> [Task]`
- [X] To-one relation + FK redundancy where useful: `Task.assignee` + `Task.assigneeID`
- [X] Many-to-many: `Task <-> [Tag]`
- [X] Nested one-to-many: `Task -> [Comment]`
- [X] Reserved-key mapping example: task `description` -> `descriptionText`
- [X] Online CRUD flows that trigger targeted re-sync instead of manual local patching
- [ ] Offline/replay (after online CRUD is stable)

## Scope Shape (Seeded vs Interactive)

### Seeded-only (reference/support data in current demo)

- [X] `User` records (used for assignee display/selection)
- [X] `Tag` metadata (`name`, etc.; membership updates still interactive through `Task`)
- [X] `Project` records in current shell (no project create/edit/delete UI in Phase 2)

### Interactive (important because they prove sync behavior)

- [X] `Task` create/update/delete in project scope
- [X] `Task.description` modal edit (`PATCH`)
- [X] `Task.assigneeID` update (including `null` clear behavior)
- [X] `Task.tags` membership replace (`PUT tag_ids`)
- [X] `Comment` create/delete under a task

## Non-Goals (Current Demo Scope)

- [X] User CRUD UI
- [X] Tag metadata CRUD UI
- [X] Project CRUD UI
- [X] Simulating HTTP protocol details (headers/status codes/router stack)
- [ ] Offline queue/outbox/replay before online CRUD is complete

## Goal

Build a demo app that proves SwiftSync can deliver:

1. [X] Reactive SwiftUI reads via `@SyncQuery` and `@SyncModel`.
2. [X] Multi-step backend loading (not a single giant JSON payload).
3. [X] Predictable sync behavior with simulated latency/failures (read path + scenario presets).
4. [ ] A path from read-only to editable flows first; offline-first is deferred until after backend stateful writes are working.

## Scope

- [X] Platform/UI: iOS + SwiftUI.
- [X] Data stack: SwiftData + SwiftSync.
- [X] Networking: fake backend service (in-process, deterministic delays/errors).
- [X] Backend storage: SQLite-backed simulator in local package `DemoBackend`
- [X] App shell: single primary flow (`Projects`) with drill-ins (`Task`, `Tag`).
- [X] Workspace setup: Xcode workspace containing:
  - `SwiftSync` package
  - `SwiftSyncDemo` app target

## Demo Domain

This demo intentionally highlights multiple relationship types with a simplified UI shell.

- `Project` -> to-many `Task`
- `Task` -> to-one `User` (`assignee`)
- `Task` <-> to-many `Tag` (many-to-many)
- `Task` -> to-many `Comment`

## Data Model (SwiftData + Syncable)

Status: `[X]` Implemented and simplified for the current showcase.

### `Project`

- `id: String` (`@PrimaryKey`)
- `name: String`
- `status: String`
- `updatedAt: Date`
- relationship: `tasks: [Task]`

### `User`

- `id: String` (`@PrimaryKey`)
- `displayName: String`
- `role: String`
- `updatedAt: Date`
- inverse relationship: `assignedTasks: [Task]`

### `Task`

- `id: String` (`@PrimaryKey`)
- `projectID: String`
- `assigneeID: String?`
- `title: String`
- `descriptionText: String`
- `state: String` (`todo`, `inProgress`, `done`)
- `updatedAt: Date`
- relationships:
  - `project: Project?`
  - `assignee: User?`
  - `tags: [Tag]`
  - `comments: [Comment]`

### `Tag`

- `id: String` (`@PrimaryKey`)
- `name: String` (e.g. `frontend`)
- `updatedAt: Date`
- inverse relationship: `tasks: [Task]`

### `Comment`

- `id: String` (`@PrimaryKey`)
- `taskID: String`
- `authorUserID: String`
- `authorName: String` (denormalized display attribute from backend payload)
- `body: String`
- `createdAt: Date`
- relationships:
  - `task: Task?`

## App Architecture

Status: `[X]` read path and Phase 2 online CRUD flows are implemented; offline/replay is still pending.

### Layers

1. [X] `DemoAPIClient` protocol + fake client implementation (now backed by `DemoBackend` SQLite simulator for reads).
2. [X] `SyncEngine` service that maps DTOs into SwiftSync `sync(...)` calls.
3. [X] `SyncContainer` as single data entry point.
4. [X] SwiftUI features reading through `@SyncQuery` / `@SyncModel`.
5. [X] `DemoBackend` local package (SQLite-backed server simulator + package tests)

## SwiftUI Feature Flows

Status: `[-]` Phase 1 read flows and Phase 2 online CRUD flows are implemented; offline/replay remains deferred.

### Tab 1: Projects

- [X] Projects list via `@SyncQuery(Project.self, in: syncContainer, sortBy: [\.name, \.id])`.
- [X] On first appearance: trigger `syncProjects()` (and tags sync in UI path).
- [X] Project detail:
  - [X] Header via `@SyncModel(Project.self, id: projectID, in: syncContainer)` (ID-owned view)
  - [X] Task list via `@SyncQuery(Task.self, relatedTo: Project.self, relatedID: projectID, ...)`
  - [X] On first appearance: trigger `syncProjectTasks(projectID:)`

### Seeded Reference Data

- [X] Users are synced as seeded reference data (assignee display + selection support).
- [X] Tags metadata is seeded reference data (task tag labels + tag drill-in).
- [X] Projects are seeded in current demo shell (no project create/edit UI planned in current Phase 2 scope).

### Task Detail

- [X] Task core model via `@SyncModel(Task.self, id: taskID, in: syncContainer)` (ID-owned view)
- [X] Assignee display via task relation
- [X] Tag list from task-tag relation (`@SyncQuery(Tag.self, relatedTo: Task.self, relatedID: taskID, ...)`)
- [X] Comments list via `@SyncQuery(Comment.self, relatedTo: Task.self, relatedID: taskID, ...)`)
- [X] On first appearance:
  - [X] `syncTaskDetail(taskID:)`
  - [X] `syncTaskComments(taskID:)`

### Description Editing Rule

- [X] In task detail, description is currently read-only.
- [X] Edit action opens modal sheet (`EditTaskDescriptionView`).
- [X] Save action goes through sync pipeline (`PATCH /tasks/{taskID}/description`).
- [X] Close modal and let reactive wrappers refresh visible task detail state.

### Tag Drill-In Flow

- From task detail, tap tag chip `#frontend`.
- [X] Navigate to `TagTasksView(tagID:)` (ID-owned destination).
- [X] Screen uses:
  - [X] `@SyncModel(Tag.self, id: tagID, in: syncContainer)`
  - [X] `@SyncQuery(Task.self, relatedTo: Tag.self, relatedID: tagID, ...)`
- [X] On first appearance: trigger `syncTagTasks(tagID:)`.

## Relationship Types Demonstrated

1. One-to-many: `Project -> [Task]`.
2. Many-to-one: `Task -> User (assignee)`.
3. Many-to-many: `Task <-> [Tag]`.
4. Nested one-to-many: `Task -> [Comment]`.
5. To-one FK + relation redundancy where useful: `Task.assigneeID` + `Task.assignee`.

## Phase 1: Read-Only, Mocked Data, Staged Fetching

Status: `[X]` Implemented (core read-only staged fetch flow).

### Behavior

1. [X] App launch:
   - Show local cache immediately via `@SyncQuery`.
   - Trigger bootstrap staged sync (projects/users/tags).
2. [X] Enter project:
   - Show cached tasks instantly.
   - Trigger `syncProjectTasks(projectID:)`.
3. [X] Enter task detail:
   - Show cached detail/comments instantly.
   - Trigger detail/comments sync calls.
4. [X] Enter tag drill-in:
   - Show cached related tasks.
   - Trigger `syncTagTasks(tagID:)`.

### Key Objective

Demonstrate relationship traversal and staged fetch behavior using a large fake dataset, with no write paths.

### Phase 1 Constraints

- [X] All screens are read-only.
- [X] No create/edit/delete UI in this phase.
- [X] Data source is fake backend only (plus local cache of synced data).

## Phase 2: Editable Online Flows

Status: `[X]` Implemented for online CRUD flows in the current demo scope.

### Requirements

1. Add create/edit capabilities while online.
2. Support creating:
   - task
   - comment
3. Continue using staged sync and reactive wrappers as primary read path.
4. Preserve modal-only task description editing rule.

### Write Endpoints Used in Phase 2

1. `POST /tasks`
2. `POST /tasks/{taskID}/comments`
3. `PATCH /tasks/{taskID}`
4. `PATCH /tasks/{taskID}/description`
5. `PUT /tasks/{taskID}/tags`

### Key Objective

Demonstrate that create/edit operations flow through SwiftSync and refresh affected screens without manual reload plumbing.

## Phase 3: Offline-First + Reconnect Replay (Deferred)

Status: `[ ]` Deferred until after SQLite-backed backend + Phase 2 writes are working.

### Requirements

1. [-] If app opens offline, render local data immediately. (local-first reads exist; no explicit offline UX flow yet)
2. [ ] Offline create/edit operations are persisted locally and queued.
3. [ ] On reconnect, queued operations replay in order.
4. [ ] UI remains responsive while replay runs.

### Additional Components

- [ ] `NetworkMonitor` abstraction (`online`/`offline`).
- [ ] `OutboxOperation` SwiftData model:
  - `id`, `kind`, `entityID`, `payload`, `createdAt`, `retryCount`, `lastError`.
- [ ] `OutboxProcessor` with:
  - ordered replay
  - exponential backoff for transient failures
  - failure surfacing after retry threshold.

### Offline Write Examples

1. [ ] Create a project.
2. [ ] Create a task.
3. [ ] Create a comment.
4. [ ] Create a user.
5. [ ] Reassign task assignee.
6. [ ] Change task description from modal.
7. [ ] Add/remove tags on a task.

All operations should update local UI immediately and queue network writes.

### Conflict Policy (Demo Default)

- [ ] Default: `serverWins` for simplicity.
- [ ] Optional debug toggle: `clientLastWriteWins`.

### Read Policy

- [X] Always read from local store (`@SyncQuery` / `@SyncModel`).
- [-] Connectivity affects sync activity only, not rendering source. (read path behaves this way; explicit offline replay system is not implemented)

## UX States to Demonstrate

- [ ] `Offline`/`Online` banner.
- [ ] `Pending changes: N` global indicator.
- [ ] Per-task pending marker when offline edits exist.
- [ ] `Last synced` timestamp in project/user/task screens.
- [X] Error banner for sync failures (current implementation)
- [X] Scenario picker (current implementation)

## Acceptance Criteria

1. [X] Project-centered app flow is fully functional for read paths (`Projects` -> `Task` -> `Tag` drill-in).
2. [X] All major relationship types are visible in user flows.
3. [X] Phase 1 is read-only and uses large fake backend content.
4. [X] Phase 2 supports creating task/comment and editing task state/description/assignee/tags.
5. [X] Task description remains editable only through modal flow.
6. [X] Tag drill-in correctly shows tasks for selected tag.
7. [ ] Phase 3 offline edits replay automatically on reconnect.
8. [X] Reactive wrappers are primary read APIs throughout UI.

## Implementation Milestones

1. [X] Workspace + app target + package wiring.
2. [X] Models + fake backend + large seeded fixtures + scenario switcher.
3. [X] Phase 1 read-only screens and staged sync calls.
4. [X] Phase 2 create/edit flows.
5. [ ] Phase 3 outbox + network monitor + replay.
6. [-] Debug panel for network/conflict simulation (scenario picker/error surfacing exist; deeper tooling remains pending)
7. [X] SQLite-backed backend simulator + backend unit tests + app client swap (tracked in `docs/planning/swiftsync-demo-backend-plan.md`)
