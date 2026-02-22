# SwiftSync Demo Backend Plan (Stateful Fake Backend, Separate from App Cache)

## Status Legend

- `[X]` done (implemented)
- `[ ]` not done yet
- `[-]` partially done / foundation exists but feature is incomplete

## Current Status (2026-02-22)

### What is done now

- [X] Backend lives in local Swift package `DemoBackend` (library + tests)
- [X] Backend state is separate from app `SyncContainer` state
- [X] App uses `DemoAPIClient` as the backend boundary
- [X] SQLite-backed server storage (projects/users/tasks/tags/comments + task_tag join table)
- [X] Deterministic seed bootstrap into SQLite backend state
- [X] Read endpoints are backed by SQLite state
- [X] Scenario delay/failure behavior remains in app fake client layer (not storage layer)
- [X] Backend unit tests for schema/bootstrap, reads, and core mutations
- [X] Demo app read path swapped to backend-backed fake client

### What is still missing

- [ ] Phase 2 write flows in the app/sync engine (backend package has test-covered mutation primitives, but app UI/write pipeline is not done yet)
- [ ] Complete backend write endpoint coverage used by Phase 2 app flows
- [ ] Finalize write contract for `PUT /tasks/{taskID}/tags` (full replace vs explicit add/remove semantics)

## Scope

- [X] In-process backend simulation (no HTTP server required)
- [X] SQLite is the backend source of truth
- [X] Backend behavior should be backend-like (validation, server-owned timestamps, relationship consistency)
- [X] Unit tests run with `swift test` in `DemoBackend`
- [ ] Offline/replay behavior is out of scope for this document (tracked in demo app plan after Phase 2 writes)

Related planning docs:

- `docs/planning/swiftsync-demo-app-plan.md`
- `docs/planning/swiftsync-demo-crud-flows-plan.md`
- `docs/planning/swiftsync-demo-field-reduction-plan.md`

## Architecture Rules

- [X] Backend code stays in `DemoBackend` local package
- [X] App local cache (`SyncContainer`) and backend SQLite state are separate sources of truth
- [X] `DemoAPIClient` remains the only boundary the app uses
- [X] Scenario presets (`fastStable`, `slowNetwork`, `flakyNetwork`, `offline`) are transport/client behavior, not storage behavior

## Fake Backend Contract

Status: `[X]` Read endpoints now run through a SQLite-backed stateful simulator in the `DemoBackend` local package.

## Backend Implementation Plan

### Storage (SQLite)

- [X] SQLite schema for projects/users/tasks/tags/comments + task_tag join table
- [X] Seed SQLite backend state from deterministic demo seed data on first init/reset
- [X] Read endpoint queries against SQLite for existing staged endpoints
- [ ] Support backend mutations in SQLite for all Phase 2 endpoints used by the app

### Behavior (Backend-like, no HTTP needed)

- [X] Server-owned timestamps/updates on mutation (`updatedAt`) for implemented mutations
- [X] Validation/error paths for invalid writes (minimal, deterministic) for implemented mutations
- [X] Stable backend-side relationship handling (task tags, comments, assignee/project foreign keys)
- [ ] Full Phase 2 write semantics exercised through app-facing endpoint methods

### Unit Tests (Required)

- [X] SQLite schema/bootstrap + seeding
- [X] Read endpoint data correctness from SQLite state
- [X] Mutation persistence (write then read reflects server-side change)
- [X] Relationship mutation correctness (comment insert)
- [ ] Coverage for every Phase 2 endpoint contract used by app flows

## Endpoints

### Read Endpoints

- [X] `GET /projects`
- [X] `GET /projects/{projectID}/tasks`
- [X] `GET /users`
- [X] `GET /users/{userID}/tasks`
- [X] `GET /tasks/{taskID}`
- [X] `GET /tasks/{taskID}/comments`
- [X] `GET /tags`
- [X] `GET /tags/{tagID}/tasks`

### Write Endpoints (Phase 2)

- [ ] `PATCH /tasks/{taskID}` (title/state/assignee)
- [ ] `PATCH /tasks/{taskID}/description` (modal edit flow)
- [ ] `PUT /tasks/{taskID}/tags` (full set replace or explicit add/remove contract)
- [ ] `POST /tasks/{taskID}/comments`
- [ ] `POST /projects`
- [ ] `POST /tasks`
- [ ] `POST /users`

## Backend Simulation Behavior

- [X] Delay per endpoint (scenario-based base + deterministic jitter)
- [X] Optional transient failures (scenario-driven flaky preset)
- [X] Deterministic scenario presets:
  - `fastStable`
  - `slowNetwork`
  - `flakyNetwork`
  - `offline`
- [-] Conflict simulation via `updatedAt` and optional `version` field (timestamps exist; explicit conflict flows are not implemented)
- [X] Large seeded dataset for realistic list stress:
  - 30 projects
  - 300 tasks
  - 40 users
  - 50 tags
  - 2,000 comments

## Execution Order (Current)

1. [ ] Finish backend write endpoint contract coverage in `DemoBackend` (+ tests)
2. [ ] Wire `DemoAPIClient` write methods to `DemoBackend`
3. [ ] Implement Phase 2 app/sync engine write flows using those methods
4. [ ] Verify end-to-end reactive refresh on write flows in the demo app
