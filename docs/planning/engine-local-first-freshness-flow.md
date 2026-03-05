# Engine Local-First Freshness Flow (Current Plan)

## Goal

One engine call per screen flow.

The screen should:

- bind to reactive local models (`@SyncQuery` / `@SyncModel`),
- call one engine method,
- render updates as data changes,
- not care whether values came from local cache or backend.

## Constraints

- No backwards-compatibility layer for old orchestration APIs.
- No caller-provided "reason" for load strategy.
- Engine chooses load strategy internally.

## Required behavior

For each screen entry point, engine decides and executes:

- local data visible immediately when available,
- network-first when local is empty/stale,
- local-first refresh when local is fresh,
- reactive store updates when backend returns changed rows.

There is no pull-to-refresh path in demo screens.

## Remaining work

### 1) Replace split orchestration with single screen calls

- [x] Keep one public engine call per screen flow (projects, project detail, task detail, task form metadata).
- [x] Remove view-level split calls (for example: separate task detail + metadata calls from the view).
- [x] Remove caller-facing load-path hints; strategy selection stays inside engine only.

Checks:

- [x] Screen lifecycle path uses one engine call.
- [x] Pull-to-refresh logic removed from all demo screens.

### 2) Keep status useful but source-agnostic to UI

- [x] Keep scope status emission for progress and failure handling.
- [x] Ensure status transitions do not require the UI to reason about local vs backend source.
- [x] Retry path is actionable and deterministic.

Checks:

- [x] Local-first flow visibly updates when backend changes land.
- [x] Network failure state is recoverable via Retry.

### 3) Remove completed/obsolete surface

- [x] Delete obsolete orchestration methods that conflict with single-call-per-screen direction.
- [x] Keep explicit network primitives only where needed for mutation follow-up.

Checks:

- [x] No duplicate orchestration API surface remains.

### 4) Verification

- [x] Add/update SwiftSync tests for deterministic status/load transitions.
- [x] Run full package tests.
- [x] Build Demo iOS scheme.
- [ ] Manual pass: confirm each screen only calls one engine load method.

## Non-goals

- Push/WebSocket/SSE integration.
- Offline mutation queue redesign.
- Broad SwiftSync core API redesign.
