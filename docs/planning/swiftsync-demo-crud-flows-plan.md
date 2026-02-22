# SwiftSync Demo CRUD Flows Plan (UI + Sync Engine + Fake Backend)

## Goal

Add clear, realistic demo flows for inserts, updates, and deletes that prove:

- app writes go to backend first (`DemoAPIClient` -> `DemoBackend`)
- SwiftSync remains the read path (`@SyncQuery` / `@SyncModel`)
- UI refresh happens through targeted sync calls, not manual local patching

Offline/outbox/replay is intentionally out of scope until these online CRUD flows are working.

## Scope Rules

- Start with online-only CRUD flows.
- Prefer simple, visible interactions over broad coverage.
- Use server-authoritative refresh after writes (targeted sync calls).
- Keep the number of writable fields small (coordinate with field-reduction plan).

Related docs:

- `docs/planning/swiftsync-demo-app-plan.md`
- `docs/planning/swiftsync-demo-backend-plan.md`
- `docs/planning/swiftsync-demo-field-reduction-plan.md`

## Recommended CRUD Slice (What to Build First)

### Inserts (Phase 2 Core)

- Create `Comment` from Task Detail
- Create `Task` from Project Detail
- Create `Project` from Projects tab
- Create `User` from Users tab

### Updates (Phase 2 Core)

- Update `Task.descriptionText` (modal edit flow)
- Update `Task.state` (inline picker/menu)
- Update `Task.assigneeID` (picker)
- Update `Task.tags` (multi-select sheet or add/remove chips)

### Deletes (Phase 2 Core, Minimal But Real)

- Delete `Comment` from Task Detail (swipe to delete)
- Delete `Task` from Project Detail (swipe to delete)

### Defer (After Core CRUD Is Stable)

- Delete `Project` (cascades and higher blast radius in demo)
- Delete `User` (referential behavior needs a deliberate rule)
- Comment editing (create/delete is enough to prove nested writes)

## UI Interaction Plan (Concrete)

## 1) Task Detail: Comments (Best First Insert/Delete Flow)

### Insert Comment

- Add composer UI at bottom of comments section or a toolbar action that opens a sheet.
- Inputs:
  - `body`
  - `authorUserID` (default selected user or simple picker)
- Save action:
  1. call `DemoAPIClient.postTaskComment(...)`
  2. call `syncTaskComments(taskID:)`
  3. optionally call `syncTaskDetail(taskID:)` if server updates task `updatedAt`

Why first:
- small payload
- obvious visible result
- parent-scoped sync (`Comment` under `Task`) is already in place

### Delete Comment

- `swipeActions` on comment row
- Confirm destructive action (alert)
- Delete action:
  1. call `DemoAPIClient.deleteTaskComment(commentID:)` (or task-scoped variant)
  2. call `syncTaskComments(taskID:)` with parent-scoped delete semantics

## 2) Task Detail: Task Updates (Most Important Update Proof)

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
  1. call `DemoAPIClient.patchTask(...)` with `state`
  2. call `syncTaskDetail(taskID:)`
  3. call parent list sync if current screen came from a list where sort/filter may change:
     - `syncProjectTasks(projectID:)` and/or
     - `syncUserTasks(userID:)` when relevant

### Reassign Assignee

- Sheet or menu listing users
- Save action:
  1. call `DemoAPIClient.patchTask(...)` with `assignee_id`
  2. sync `task` detail
  3. sync affected lists:
     - old assignee tasks slice (if known)
     - new assignee tasks slice
     - project tasks slice (task row contents changed)

### Edit Tags (Many-to-many)

- Sheet with multi-select tag list
- Save action sends full selected set (recommended):
  1. call `DemoAPIClient.putTaskTags(taskID:tagIDs:)`
  2. `syncTaskDetail(taskID:)` (for `tag_ids` on task payload)
  3. `syncTags()` only if tag metadata changed (usually not needed)
  4. `syncTagTasks(tagID:)` for impacted tags if you need tag drill-in to reflect immediately

Recommended simplification:
- Refresh only the current task detail first
- Let tag drill-in update on next open/refresh unless stale drill-in is visible in the same session

## 3) Project Detail: Task Insert/Delete

### Create Task

- Toolbar `+` on Project Detail
- Sheet form:
  - `title` (required)
  - `state` (default)
  - optional `assignee`
  - optional `description`
- Save action:
  1. call `DemoAPIClient.postTask(projectID:...)`
  2. call `syncProjectTasks(projectID:)`
  3. if assignee set, call `syncUserTasks(userID:)` for the selected user (optional phase-2b refinement)

### Delete Task

- `swipeActions` in Project Detail task list
- Confirm delete alert
- Delete action:
  1. call `DemoAPIClient.deleteTask(taskID:)`
  2. call `syncProjectTasks(projectID:)` (authoritative slice + delete pass)
  3. optionally sync related slices if currently visible elsewhere (defer unless needed)

## 4) Root Lists: Project/User Insert

### Create Project

- Toolbar `+` in Projects tab
- Simple sheet form (`name`, maybe `status`)
- Save:
  1. call `DemoAPIClient.postProject(...)`
  2. call `syncProjects()`

### Create User

- Toolbar `+` in Users tab
- Simple sheet form (`displayName`, maybe `role`)
- Save:
  1. call `DemoAPIClient.postUser(...)`
  2. call `syncUsers()`

## Sync Engine Plan (App Layer)

Add explicit write methods to `DemoSyncEngine` for UI screens to call.

Recommended pattern:

- `createProject(...)`
- `createUser(...)`
- `createTask(...)`
- `createComment(...)`
- `updateTaskDescription(...)`
- `updateTask(...)`
- `replaceTaskTags(...)`
- `deleteTask(...)`
- `deleteComment(...)`

Each method should:

1. call API client write endpoint
2. trigger the minimum set of sync reads needed to refresh affected UI
3. reuse `syncOperation(...)` error/loading behavior

Do not patch SwiftData rows directly in UI code.

## API Client Plan (Demo App Boundary)

Extend `DemoAPIClient` with write methods matching the CRUD slice.

### Phase 2a (First Wave)

- `postTaskComment`
- `deleteTaskComment`
- `patchTaskDescription`
- `patchTask`

### Phase 2b (Second Wave)

- `putTaskTags`
- `postTask`
- `deleteTask`
- `postProject`
- `postUser`

Why this order:
- starts with Task Detail flows (smallest UI surface, highest demo value)
- then expands to root and list-level create/delete

## Fake Backend Plan (Coordination)

`DemoBackend` must expose and test the write operations used by the app in the same phase order.

Required backend behavior for all writes:

- validate references (`project_id`, `assignee_id`, etc.)
- server-owned timestamps (`updatedAt`, `createdAt`)
- return backend-shaped payload keys (snake_case)
- enforce relationship consistency (including `task_tags`)

## TDD Plan (Required)

## 1) DemoBackend Package Tests First

For each endpoint before wiring UI:

1. add failing `DemoBackend` unit test
2. implement backend endpoint
3. make test pass

Examples:

- `PATCH /tasks/{id}/description` updates `description` and bumps `updated_at`
- `POST /tasks/{id}/comments` inserts row and appears in task comments query
- `DELETE /tasks/{id}` removes task and cascades task comments/task_tags as expected

## 2) App Layer Tests / Verification

Keep this lightweight initially:

- build + manual verification on the demo app for each flow
- add focused demo tests only where behavior is easy to isolate

## Execution Order (Recommended)

1. Finalize reduced field set for Phase 2 CRUD forms (coordinate with field-reduction plan)
2. Implement + test backend endpoints for Task Detail flows (`comment`, `description`, `task patch`)
3. Add `DemoAPIClient` write methods for those endpoints
4. Add `DemoSyncEngine` write methods + targeted post-write sync calls
5. Implement Task Detail UI for comment create/delete + description/state/assignee updates
6. Implement + test backend endpoints for task create/delete + tags replace
7. Wire Project Detail task create/delete UI
8. Implement + test backend endpoints for project/user create
9. Wire root-list create UI for projects/users
10. Do a cleanup pass (copy, errors, loading states, destructive confirmations)

## Acceptance Criteria

1. Demo has visible insert, update, and delete flows (not read-only only).
2. All writes go through `DemoSyncEngine` + `DemoAPIClient`, not direct local model mutation.
3. Post-write UI refresh is driven by targeted sync calls.
4. `DemoBackend` unit tests cover all shipped write endpoints.
5. Demo remains online-only for Phase 2; offline/outbox work stays deferred.
