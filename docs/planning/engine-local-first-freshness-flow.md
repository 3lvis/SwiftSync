# Engine Local-First Freshness Flow (No Default Polling)

## Why this change

The current demo behavior includes always-on polling loops in screen views. That was
useful to force race conditions during development, but it is not the best default
pattern to teach.

For a SwiftSync best-practices demo, we want a simpler and more realistic contract:

- local data renders first when it is fresh enough
- network refresh runs in the background when needed
- views update reactively from SwiftData changes
- polling is debug-only stress tooling

This keeps the architecture clear and avoids teaching "always poll" as the default.

---

## Target flow

### Mental model

1. **Connect:** screen binds to store-backed data (`@SyncQuery` / `@SyncModel`).
2. **Decide freshness:** engine checks whether local data is usable for this scope.
3. **Load:**
   - local fresh enough -> show local now, refresh in background
   - local missing or too stale -> network-first, then sync to store
4. **Propagate:** sync writes to SwiftData; view updates through reactive query.
5. **Signal status:** engine emits sync-state events (loading, refreshing, stale, error).

Important: the data stream is SwiftData itself. The extra stream is for sync status,
not a second source of model payloads.

---

## Policy decisions

1. **No default polling loops in production UX paths**
   Remove recurring `.task { while ... sleep(...) }` loops from normal screens.

2. **Keep pull-to-refresh**
   Manual refresh remains the explicit user override.

3. **Add freshness-gated local-first reads**
   The engine decides whether local data is acceptable based on age and emptiness.

4. **Keep mutations network-first**
   `create/update/delete/replace` continue to call server first, then re-sync.

5. **Retain stress testing via explicit debug mode**
   Polling becomes a targeted stress tool, enabled only when intentionally turned on.

---

## Freshness model (initial version)

Use per-scope TTL with conservative defaults:

- `TaskStateOption`, `User`, `UserRoleOption`: 24h
- `Project` list: 5m
- `Project` tasks: 2m
- `Task` detail: 30s

Decision rule:

- if local set is empty -> network-first
- if local set exists and age <= TTL -> local-first + background refresh
- if local set exists and age > TTL -> network-first (do not show stale-first)

Notes:

- "Age" is per scope based on a tracked `lastSuccessfulSync` timestamp.
- TTL values are config, not hardcoded in view code.

---

## Engine surface direction

Keep API easy to read at call sites.

- **Data access:** `local*` read helpers for metadata/form needs
- **Network refresh:** existing `sync*` methods
- **Orchestration:** lightweight engine method per screen scope that applies freshness
- **Status stream:** published sync state per scope for UI messaging/spinners/errors

Example shape:

```swift
enum SyncScope {
    case projects
    case projectTasks(projectID: String)
    case taskDetail(taskID: String)
    case taskStates
    case users
    case userRoles
}

enum SyncPhase {
    case idle
    case loadingNetworkOnly
    case showingLocalRefreshing
    case refreshed
    case failed(String)
}
```

---

## Work plan

### 1) Move from default polling to on-demand Earthquake Mode (first priority)
- [x] Remove recurring polling loops from normal screen lifecycle (`ProjectDetailView`, `TaskDetailView`).
- [x] Keep existing normal behavior: initial `.task` sync + pull-to-refresh.
- [x] Add DEBUG-only shake trigger on active screen.
- [x] On shake, show confirmation prompt: "Stress test this screen?"
- [x] If confirmed, run finite stress session (adds/edits/deletes + refresh overlap) scoped to that screen.
- [x] Add clear in-app indicator while stress session is running.
- [x] Ensure stress mode is opt-in and defaults OFF every launch.

Checks:
- [ ] With no shake action, there is no periodic background polling.
- [ ] With shake + confirm, stress runner starts and can be stopped.
- [ ] Pull-to-refresh and normal mutation flows remain unchanged.
- [ ] UI copy clearly states this is debug stress tooling, not normal engine behavior.

Validation approach:
- [ ] Add targeted tests only for core stress-runner logic where deterministic and low-cost.
- [ ] Use manual verification for shake interaction and screen-specific UX states.

### 2) Introduce freshness policy in engine
- [ ] Add TTL policy map by `SyncScope` and local metadata for last successful sync time.
- [ ] Add helper to evaluate `empty / fresh / stale` for a scope.
- [ ] Persist or reliably derive per-scope timestamps across app lifetime.

Checks:
- [ ] Local fresh path is selected when data exists and age is within TTL.
- [ ] Network-first path is selected when local data is empty or stale.

Validation approach:
- [ ] Add focused tests for freshness decision logic.
- [ ] Verify through targeted manual flows.

### 3) Add scope-level sync status stream
- [ ] Add published state per scope (phase + error payload).
- [ ] Ensure state updates are deterministic for both success and failure paths.
- [ ] Keep current global `isSyncing` for simple top-level indicators.

Checks:
- [ ] UI can distinguish local-first refresh vs network-first load.
- [ ] Failure states are actionable and do not break normal interaction.

Validation approach:
- [ ] Verify status transitions through direct behavior checks in demo UI.
- [ ] Add targeted tests for ordering logic.

### 4) Implement local-first orchestration paths
- [ ] Add engine entry points for screen flows that apply freshness policy.
- [ ] Keep low-level `sync*` methods as explicit network refresh primitives.
- [ ] Use `local*` helpers for metadata reads in forms.

Checks:
- [ ] Task form opens with cached metadata immediately when fresh.
- [ ] Stale metadata path goes network-first.
- [ ] Retry remains network-only and bypasses local-first shortcut.

Validation approach:
- [ ] Cover highest-risk branches with tests.
- [ ] Verify with scenario-based manual runs.

### 5) Document the pattern clearly
- [ ] Update demo docs to describe local-first freshness flow and Earthquake Mode boundaries.
- [ ] Add "what this teaches" section for SwiftSync adopters.
- [ ] Include concise troubleshooting for stale UI vs stale cache policy.

Checks:
- [ ] Docs match implemented behavior and method names.
- [ ] A new reader can explain normal flow vs debug flow without reading code.

---

## Non-goals for this pass

- Push/WebSocket/SSE integration.
- Full offline mutation queue design.
- Large refactor of SwiftSync core library API.

This pass is focused on making the demo teach the right default sync pattern.

---

## Files expected to change (implementation phase)

- `Demo/Demo/Sync/DemoSyncEngine.swift`
- `Demo/Demo/Features/Projects/ProjectsTabView.swift`
- `Demo/Demo/Features/TaskDetail/TaskDetailView.swift`
- `Demo/Demo/Features/TaskFormSheet.swift`
- `Demo/DemoTests/` (new/updated tests)
- docs update(s) in `docs/planning/` and/or `docs/project/`

---

## Status

Planned and ready for TDD implementation.
