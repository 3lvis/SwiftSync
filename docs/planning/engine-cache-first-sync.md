# Engine Cache-First Sync

## Problem

The `DemoSyncEngine` goes straight to the network for every sync call. There is no
distinction between "I need fresh data right now" and "show me what's on disk, then
quietly refresh in the background". This pushes the cache-vs-network decision into
the UI layer, which is the wrong place for it.

The symptom that surfaced this: `TaskFormSheet` showed a loading spinner and fired a
network call for `TaskStateOption` every time the form opened, even though the
bootstrap sync had already populated those rows on first launch. A one-off disk-first
check was added directly in `TaskFormSheet.loadData()` as a workaround.

That fix works, but it is in the wrong layer and does not scale — every new form or
view that needs reference data would have to re-implement the same pattern.

---

## Current State (as of 2026-03-04)

### Engine — all reads go straight to network

Every public read-sync method on `DemoSyncEngine` calls its `*Internal()` counterpart
unconditionally, which calls `apiClient.*` before touching the store:

| Method | Trigger | Network |
|---|---|---|
| `syncProjects()` | viewDidLoad, pull-to-refresh | always |
| `syncProjectTasks(projectID:)` | appear, pull-to-refresh, polling (10 s) | always |
| `syncTaskDetail(taskID:)` | appear, pull-to-refresh, polling (14 s) | always |
| `syncTaskStates()` | appear, form open, retry button | always |
| `syncUsers()` | bootstrap only | always |
| `syncUserRoles()` | bootstrap only | always |

Mutation methods (`createTask`, `updateTask`, `deleteTask`, `replaceTaskReviewers`,
`replaceTaskWatchers`) must always go to the network first — these are not candidates
for caching.

### UI — one ad-hoc disk-first patch

`TaskFormSheet.loadData()` is the only place that does disk-first:

```swift
let cached = (try? editContext.fetch(stateDescriptor)) ?? []
if !cached.isEmpty {
    taskStateOptions = cached       // disk hit — done
} else {
    loadTaskStates()                // cold launch fallback — hits network
}
```

This is the pattern we want to move into the engine so all callers get it for free.

### Why `@SyncQuery`-backed views are less affected

Views using `@SyncQuery` (ProjectsViewController, ProjectDetailView, TaskDetailView)
already show cached store data instantly — the reactive query fires from the store on
first render. The engine's network sync then updates what's already visible.
The problem is most visible in forms that manually manage `@State` arrays (like
`TaskFormSheet`) because they have nothing to show until the engine delivers data.

---

## Root Cause

The engine is a pure network-sync layer with no awareness of what is already in the
store. It has no concept of:

- "Is this data already available locally?"
- "Should I deliver cached data to the caller before going to the network?"
- "Is the caller interested in the first result (fast) or the freshest result (slow)?"

---

## Proposed Solution

### Two-phase read pattern

For every read-only sync method, the engine should:

1. **Immediately** fetch from the local store and deliver the result
2. **Then** fire the network refresh in the background

The caller gets fast local data first, and the UI updates again when the network
response arrives and syncs into the store.

This is a standard "stale-while-revalidate" pattern. It eliminates loading states for
reference data that has already been bootstrapped.

### API shape options

**Option A — Separate method per phase (explicit)**

```swift
// Sync engine public surface
func localTaskStates() -> [TaskStateOption]         // immediate, no async
func syncTaskStates() async                          // network refresh, existing name
```

The form calls `localTaskStates()` synchronously on open, populates the picker
immediately, then calls `syncTaskStates()` in a `.task` to refresh in the background.

Pro: no behaviour change for existing callers of `syncTaskStates()`.  
Con: two calls at every call site.

**Option B — Single method, always cache-first (implicit)**

```swift
func syncTaskStates() async   // disk first, then network — always
```

Internally: fetch from store → notify → network refresh → notify again.

Pro: call sites stay identical.  
Con: callers that want network-only (e.g. retry button) get the disk result too, which
is benign but unnecessary.

**Option C — AsyncStream / callback per emission**

```swift
func taskStatesStream() -> AsyncStream<[TaskStateOption]>
// emits: local result immediately, then network result when it arrives
```

Pro: caller can observe both emissions naturally.  
Con: materially more complex, likely overkill for this demo.

### Recommended approach: Option A

Keep `syncTaskStates()` (and peers) as network-only methods. Add lightweight
`local*()` query methods to the engine that read from `mainContext`. Forms call the
local method first for instant display, then fire the background sync.

The engine owns the fetch logic and sort order. The UI calls two well-named methods
and never touches `FetchDescriptor` directly.

```swift
// Engine additions (read from mainContext, synchronous)
func localTaskStates() -> [TaskStateOption]
func localUsers() -> [User]

// TaskFormSheet becomes:
private func loadData() {
    users = syncEngine.localUsers()
    taskStateOptions = syncEngine.localTaskStates()
    // Background refresh — updates UI if server has newer data
    _Concurrency.Task { await syncEngine.syncTaskStates() }
}
```

The `editContext` cross-context issue: `TaskFormSheet` uses an `editContext` separate
from `mainContext` for SwiftData safety (so that assigning `User` objects to
`draft.reviewers` doesn't cross context boundaries). The `local*()` methods return
`mainContext` objects. The form would need to re-fetch those IDs into `editContext`
when assigning to relationship arrays, or the `local*()` methods could accept a
context parameter.

This is the primary open design question before implementation.

---

## Open Questions

1. **Context parameter on `local*()` methods?**
   Should `localUsers(in: ModelContext) -> [User]` accept a context so the form can
   pass its `editContext` and get objects safe to assign to relationships? Or should
   the local methods always return `mainContext` objects and the form resolves
   cross-context assignment separately (fetch by ID from `editContext`)?

2. **Scope — which methods get a `local*()` counterpart?**
   Candidates: `TaskStateOption`, `User`. Projects and Tasks are already served by
   `@SyncQuery` reactive queries and do not need `local*()` equivalents.

3. **Polling loops — should they also be cache-first?**
   The 10 s and 14 s polling loops in `ProjectDetailView` and `TaskDetailView` are
   pure background refreshes. They do not need cache-first behaviour (the UI already
   shows live `@SyncQuery` data). Leave them network-only.

4. **Retry button in `TaskFormSheet`**
   The "Retry Loading States" button exists for the cold-launch fallback path
   (network call failed, store is empty). If `syncTaskStates()` becomes cache-first,
   the retry button should still force a network-only refresh. Option A preserves this
   naturally — the retry button calls `syncTaskStates()` which remains network-only.

---

## Files to Touch (when implemented)

- `Demo/Demo/Sync/DemoSyncEngine.swift` — add `local*()` query methods
- `Demo/Demo/Features/TaskFormSheet.swift` — use `syncEngine.localTaskStates()` and
  `syncEngine.localUsers()` instead of direct `editContext` fetches; fire background
  sync separately

No library (`Sources/SwiftSync/`) changes required.

---

## Status

Deferred. Captured here for the next pass.
