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
- [X] SQLite-backed server storage (projects/users/tasks)
- [X] Deterministic seed bootstrap into SQLite backend state
- [X] Read endpoints are backed by SQLite state
- [X] Scenario delay/failure behavior remains in app fake client layer (not storage layer)
- [X] Backend unit tests for schema/bootstrap, reads, and core mutations
- [X] Demo app read path swapped to backend-backed fake client

### What is still missing

- [ ] Offline/outbox replay semantics (intentionally deferred until after online CRUD)

## Scope

- [X] In-process backend simulation (no HTTP server required)
- [X] SQLite is the backend source of truth
- [X] Backend behavior should be backend-like (validation, server-owned timestamps, relationship consistency)
- [X] Unit tests run with `swift test` in `DemoBackend`
- [ ] Offline/replay behavior is out of scope for this document (tracked in demo app plan after Phase 2 writes)

Related planning docs:

- `docs/planning/swiftsync-demo-app-plan.md`
- `docs/planning/swiftsync-demo-crud-flows-plan.md`

## Backend Purpose (for the Demo)

Provide a backend-like source of truth that is separate from the app cache, so demo writes and reads behave like a real system without building a real HTTP service.

The backend exists to prove:

- server-owned state changes (timestamps, validation, relationship consistency)
- app/backend separation of truth (`SyncContainer` cache vs backend SQLite)
- deterministic read/write behavior for SwiftSync demo flows

## Backend Mantra

- Act like a backend where it matters (state, validation, timestamps, consistency).
- Drop protocol/server complexity that the app does not need (HTTP stack, auth, deployment).
- Keep the backend boundary explicit through `DemoAPIClient`.
- Test backend behavior with `swift test` before wiring app flows.

## Backend Non-Goals (Current Scope)

- [X] Real HTTP server/router
- [X] Auth/session management
- [X] Multi-client concurrency simulation
- [X] Production backend architecture concerns
- [ ] Offline/outbox replay semantics before online CRUD endpoints are complete

## Architecture Rules

- [X] Backend code stays in `DemoBackend` local package
- [X] App local cache (`SyncContainer`) and backend SQLite state are separate sources of truth
- [X] `DemoAPIClient` remains the only boundary the app uses
- [X] Scenario presets (`fastStable`, `slowNetwork`, `flakyNetwork`, `offline`) are transport/client behavior, not storage behavior

## Fake Backend Contract

Status: `[X]` Read endpoints now run through a SQLite-backed stateful simulator in the `DemoBackend` local package.

## Backend Implementation Plan

### Storage (SQLite)

- [X] SQLite schema for projects/users/tasks
- [X] Seed SQLite backend state from deterministic demo seed data on first init/reset
- [X] Read endpoint queries against SQLite for existing staged endpoints
- [X] Support backend mutations in SQLite for all Phase 2 endpoints used by the app

### Behavior (Backend-like, no HTTP needed)

- [X] Server-owned timestamps/updates on mutation (`updatedAt`) for implemented mutations
- [X] Validation/error paths for invalid writes (minimal, deterministic) for implemented mutations
- [X] Stable backend-side relationship handling (assignee/reviewer/author/project foreign keys)
- [X] Full Phase 2 online write semantics exercised through app-facing endpoint methods

### Unit Tests (Required)

- [X] SQLite schema/bootstrap + seeding
- [X] Read endpoint data correctness from SQLite state
- [X] Mutation persistence (write then read reflects server-side change)
- [X] Coverage for every Phase 2 backend endpoint contract used by app flows

## Endpoints

### Read Endpoints

- [X] `GET /projects`
- [X] `GET /projects/{projectID}/tasks`
- [X] `GET /users` (seeded reference data for assignee display/selection)
- [X] `GET /tasks/{taskID}`
### Write Endpoints (Phase 2)

- [X] `PATCH /tasks/{taskID}` (state/assignee in current demo scope)
- [X] `PATCH /tasks/{taskID}/description` (modal edit flow)
- [X] `POST /tasks`
- [X] `DELETE /tasks/{taskID}`

## Backend Simulation Behavior

- [X] Delay per endpoint (scenario-based base + deterministic jitter)
- [X] Optional transient failures (scenario-driven flaky preset)
- [X] Deterministic scenario presets:
  - `fastStable`
  - `slowNetwork`
  - `flakyNetwork`
  - `offline`
- [-] Conflict simulation via `updatedAt` and optional `version` field (timestamps exist; explicit conflict flows are not implemented)
- [X] Curated seeded dataset for coherent demo storytelling:
  - 3 projects
  - 12 tasks
  - 6 users

## Execution Order (Current)

1. [X] Finish backend write endpoint contract coverage in `DemoBackend` (+ tests)
2. [X] Wire `DemoAPIClient` write methods to `DemoBackend`
3. [X] Implement Phase 2 app/sync engine write flows using those methods
4. [X] Verify end-to-end reactive refresh on write flows in the demo app (build/manual flow wiring complete)
