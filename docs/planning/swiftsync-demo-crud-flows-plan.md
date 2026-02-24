# SwiftSync Demo CRUD Flows Plan (UI + Sync Engine + Fake Backend)

## Goal

Add clear, realistic demo flows for inserts, updates, and deletes that prove:

- app writes go to backend first (`DemoAPIClient` -> `DemoBackend`)
- SwiftSync remains the read path (`@SyncQuery` / `@SyncModel`)
- UI refresh happens through targeted sync calls, not manual local patching

Offline/outbox/replay is intentionally out of scope until these online CRUD flows are working.

## Current Status (2026-02-22)

- [X] Core online CRUD slice implemented in demo UI + `DemoSyncEngine`
- [X] `DemoAPIClient` write methods wired to `DemoBackend`
- [X] `DemoBackend` write endpoints + unit tests for shipped Phase 2 flows
- [ ] Offline/outbox/replay (deferred)

## Scope Rules

- Start with online-only CRUD flows.
- Prefer simple, visible interactions over broad coverage.
- Use server-authoritative refresh after writes (targeted sync calls).
- Keep the number of writable fields small (coordinate with the model/feature map).
- Keep support/reference entities seeded unless CRUD adds a new SwiftSync behavior.

## CRUD Flow Mantra

- Build the smallest interactive flow that proves the sync behavior.
- Do not add CRUD for seeded reference entities (`User`, `Project`) in current scope.
- Backend write first, then targeted sync reads refresh the UI.
- Avoid manual local patching in UI code.

## Core CRUD Showcase (Current Phase 2 Target)

- `Task` create/delete in a project (one-to-many parent-scoped list refresh)
- `Task` updates (`description`, `state`, `assignee`) (to-one/FK + partial updates)

Related docs:

- `docs/planning/swiftsync-demo-app-plan.md`
- `docs/planning/swiftsync-demo-backend-plan.md`

## Recommended CRUD Slice (What to Build First)

### Inserts (Phase 2 Core)

- Create `Task` from Project Detail

### Updates (Phase 2 Core)

- Update `Task.descriptionText` (modal edit flow)
- Update `Task.state` (inline picker/menu)
- Update `Task.assigneeID` (picker)

### Deletes (Phase 2 Core, Minimal But Real)

- Delete `Task` from Project Detail (swipe to delete)

### Defer (After Core CRUD Is Stable)

- Delete `Project` (cascades and higher blast radius in demo)
- Delete `User` (referential behavior needs a deliberate rule)

## UI Interaction Plan (Concrete)

## 1) Task Detail: Task Updates (Most Important Update Proof)

### Edit Description (Modal)

- Keep current planned modal-only rule
- Toolbar button `Edit Description`
- Sheet with `TextEditor`
- Save action:
  1. call `DemoAPIClient.patchTaskDescription(taskID:description:)`
  2. call `syncTaskDetail(taskID:)`

### Edit State

- Inline `Menu` / segmented picker in task detail header
- Save immediately on selection (no extra form submit)
- Action:
  1. call `DemoAPIClient.patchTaskState(...)`
  2. call `syncTaskDetail(taskID:)`
  3. call parent list sync if current screen came from a list where sort/filter may change:
     - `syncProjectTasks(projectID:)` when relevant

### Reassign Assignee

- Sheet or menu listing users
- Save action:
  1. call `DemoAPIClient.patchTaskAssignee(...)`
  2. sync `task` detail
  3. sync affected lists:
     - old assignee tasks slice (if known)
     - new assignee tasks slice
     - project tasks slice (task row contents changed)

## 3) Project Detail: Task Insert/Delete

### Create Task

- Toolbar `+` on Project Detail
- Sheet form:
  - `title` (required)
  - `state` (default)
  - optional `assignee`
  - optional `description`
- Save action:
  1. call `DemoAPIClient.createTask(projectID:...)`
  2. call `syncProjectTasks(projectID:)`
  3. keep task detail/project list refresh scoped to the project slice

### Delete Task

- `swipeActions` in Project Detail task list
- Confirm delete alert
- Delete action:
  1. call `DemoAPIClient.deleteTask(taskID:)`
  2. call `syncProjectTasks(projectID:)` (authoritative slice + delete pass)
  3. optionally sync related slices if currently visible elsewhere (defer unless needed)

## Sync Engine Plan (App Layer)

Add explicit write methods to `DemoSyncEngine` for UI screens to call.

Recommended pattern:

- `createTask(...)`
- `updateTaskDescription(...)`
- `updateTaskState(...)`
- `updateTaskAssignee(...)`
- `deleteTask(...)`

Each method should:

1. call API client write endpoint
2. trigger the minimum set of sync reads needed to refresh affected UI
3. reuse `syncOperation(...)` error/loading behavior

Do not patch SwiftData rows directly in UI code.

## API Client Plan (Demo App Boundary)

Extend `DemoAPIClient` with write methods matching the CRUD slice.

Implemented in current demo:

- `patchTaskDescription`
- `patchTaskState`
- `patchTaskAssignee`
- `createTask`
- `deleteTask`

## Fake Backend Plan (Coordination)

`DemoBackend` must expose and test the write operations used by the app in the same phase order.

Required backend behavior for all writes:

- validate references (`project_id`, `assignee_id`, etc.)
- server-owned timestamps (`updatedAt`, `createdAt`)
- return backend-shaped payload keys (snake_case)
- enforce relationship consistency

## TDD Plan (Required)

## 1) DemoBackend Package Tests First

For each endpoint before wiring UI:

1. add failing `DemoBackend` unit test
2. implement backend endpoint
3. make test pass

Examples:

- `PATCH /tasks/{id}/description` updates `description` and bumps `updated_at`
- `DELETE /tasks/{id}` removes task and cascades related rows as expected

## 2) App Layer Tests / Verification

Keep this lightweight initially:

- build + manual verification on the demo app for each flow
- add focused demo tests only where behavior is easy to isolate

## Execution Order (Recommended)

1. [X] Finalize reduced field set for Phase 2 CRUD forms (coordinate with the model/feature map)
2. [X] Implement + test backend endpoints for Task Detail flows (`description`, `task patch`)
3. [X] Add `DemoAPIClient` write methods for those endpoints
4. [X] Add `DemoSyncEngine` write methods + targeted post-write sync calls
5. [X] Implement Task Detail UI for description/state/assignee updates
6. [X] Implement + test backend endpoints for task create/delete
7. [X] Wire Project Detail task create/delete UI
8. [X] Do a cleanup pass (copy, errors, loading states, destructive confirmations)

## Acceptance Criteria

1. [X] Demo has visible insert, update, and delete flows (not read-only only).
2. [X] All writes go through `DemoSyncEngine` + `DemoAPIClient`, not direct local model mutation.
3. [X] Post-write UI refresh is driven by targeted sync calls.
4. [X] `DemoBackend` unit tests cover all shipped write endpoints.
5. [X] Demo remains online-only for Phase 2; offline/outbox work stays deferred.
