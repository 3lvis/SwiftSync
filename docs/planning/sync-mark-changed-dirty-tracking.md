# Suspected Bug: SwiftData Dirty-Tracking Gap in To-Many Relationships

**Status:** Unconfirmed — test to reproduce pending  
**Affects:** Persistent (on-disk) SQLite stores only — in-memory stores are believed to be unaffected  
**Risk if confirmed:** `@SyncModel` / `@SyncQuery` serve stale relationship data until the next background poll

---

## Hypothesis

SwiftData (built on Core Data) may only mark a model's **own store row** dirty when a **scalar column**
on that model changes. Writing to a to-many relationship may only dirty the **join-table rows** — not
the owning row.

If true, after `syncApplyToManyForeignKeys` writes a new membership set (e.g., adding a reviewer to a
task), the Task's store row is untouched. The Task's `PersistentIdentifier` is then absent from the
`NSManagedObjectContextDidSave` notification's `updatedObjects`. SwiftSync's reactive pipeline never
hears about the Task. The UI stays stale until the next background poll.

### Why it may only manifest on persistent stores

In-memory SQLite stores behave differently — SwiftData is believed to always surface the owning row's
identifier in the save notification regardless of whether a scalar changed. This matters for tests:

- Unit tests using `isStoredInMemoryOnly: true` would **pass even if the bug exists** — the assertion
  `notificationIDs.contains(taskID)` would be true in-memory whether or not the bug affects persistent
  stores.
- The bug would only show on device and Simulator using a persistent on-disk store.

---

## The Reactive Pipeline

SwiftSync's UI update chain:

```
background ModelContext.save()
    ↓
SyncContainer.modelContextDidSave(_:)         // observes NSManagedObjectContextDidSave
    → collects changedIDs from notification
    → faults each ID into mainContext
    → posts SyncContainer.didSaveChangesNotification
        ↓
SyncModelObserver / SyncQueryObserver
    → shouldReload() checks changedTypeNames ∩ observedTypeNames
    → reload() re-fetches from mainContext
    → @Published var model/rows fires
        ↓
SwiftUI re-renders the view
```

The entire chain depends on the owning model's `PersistentIdentifier` appearing in the save
notification's changed identifiers. If it is absent, nothing downstream ever reloads.

---

## Current Code — Where the Gap Would Occur

`syncApplyToManyForeignKeys` (Overload 2, `Core.swift` ~line 353) is the write site:

```swift
if modelIDSet(current) != modelIDSet(next) {
    owner[keyPath: relationship] = next
    return true   // ← relationship written, but owning row may not be dirtied
}
```

There is no mechanism today to force the owning row dirty after a to-many write.
`SyncUpdatableModel` has no `syncMarkChanged()` requirement. The `@Syncable` macro generates no such
call. The gap is silent: `syncApplyToManyForeignKeys` returns `true` (relationship changed) but the
owning model's `PersistentIdentifier` may never reach `SyncContainer.modelContextDidSave`.

### Affected relationship pattern

Models that use to-many relationships **with no explicit `@Relationship` inverse anchor** are the
clearest risk — which matches the Demo's `Task.reviewers` and `Task.watchers`:

```swift
// Task has reviewers and watchers with no declared inverse on User
var reviewers: [User]
var watchers: [User]
```

Models with a proper bidirectional `@Relationship(inverse:)` declaration may behave differently
because Core Data can track the change through the inverse side, but this is not guaranteed.

---

## Investigation Plan

### Step 1 — Write a red test (persistent store, background context)

Write a unit test that:

1. Creates a **persistent on-disk** `ModelContainer` (temp file URL, cleaned up in `tearDown`)
2. Creates a `SyncContainer` wrapping it (so `modelContextDidSave` is wired up)
3. Seeds an owner model (e.g., a task with no tags) via a **background context** and saves
4. Listens for `SyncContainer.didSaveChangesNotification`
5. Performs a to-many-only sync (adds tags, no scalar change) via a background context and saves
6. Asserts the owner's `PersistentIdentifier` is in `changedIDs` from the notification

This test **must fail** without any fix. If it passes, either:
- the bug does not exist on the current platform/OS version, or
- some other code path is incidentally dirtying the scalar

Either outcome is useful signal.

### Step 2 — Confirm the in-memory variant passes without a fix

Run the same logical test with `isStoredInMemoryOnly: true` and confirm it passes — establishing
that in-memory tests cannot catch this class of bug.

### Step 3 — Implement a fix (only after Step 1 is red)

**Proposed fix: `syncMarkChanged()`**

Add a `syncMarkChanged()` requirement to `SyncUpdatableModel` with a default no-op:

```swift
public protocol SyncUpdatableModel: SyncModelable {
    // ...existing requirements...

    /// Forces a no-op write on a scalar property so SwiftData marks the model's
    /// persistent store row as dirty after a to-many relationship change.
    func syncMarkChanged()
}

public extension SyncUpdatableModel {
    func syncMarkChanged() {}  // default no-op for hand-written conformances
}
```

Have `@Syncable` generate a real implementation using the identity property:

```swift
// Generated by @Syncable
func syncMarkChanged() {
    self.id = self.id   // no-op scalar write — forces Core Data to mark the row dirty
}
```

Call it in `syncApplyToManyForeignKeys` after every real membership change:

```swift
if modelIDSet(current) != modelIDSet(next) {
    owner[keyPath: relationship] = next
    owner.syncMarkChanged()   // ← forces dirty bit on owning row
    return true
}
```

Constrain Overload 2's `Owner` to `SyncUpdatableModel` to make the call statically guaranteed.

### Step 4 — Confirm the red test turns green

Re-run the persistent-store test from Step 1. It should now pass.

---

## Open Questions

### 1. Is the bug actually reproducible?

During the `debug/reviewer-watcher-stale-ui` investigation (branching from `85b7fa0`, before any fix),
the gap was **not observed** — `Demo.Task` still appeared in `changedTypeNames` after every
relationship save. The Demo uses a persistent on-disk SQLite store, so the gap should have manifested.
Possible explanations:

- Simulator-specific SQLite behavior that always surfaces the owning row
- An incidental scalar write elsewhere in the sync path that happened to touch the Task row
- The gap only triggers on certain OS versions or SQLite configurations

A focused test (Step 1) will settle this.

### 2. The actual root cause of the visible stale-UI bug was different

The reviewer/watcher stale-UI symptom turned out to be a **sync ordering issue** in `DemoSyncEngine`:
`syncProjectTasksInternal` was running *after* `syncTaskDetailInternal`, writing a stale project-list
snapshot (which contained the pre-save relationship membership) on top of the correct data that
`syncTaskDetailInternal` had just written. Fixed by swapping the order so `syncTaskDetailInternal`
always runs last (commit `3519db9` on `debug/reviewer-watcher-stale-ui`).

The dirty-tracking gap is a **separate, distinct bug** that may exist independently of the ordering
fix.

### 3. Hand-written conformances get a no-op `syncMarkChanged()`

If the fix is implemented, the default no-op means any model that manually conforms to
`SyncUpdatableModel` (rather than using `@Syncable`) will silently not dirty its row after a to-many
change. This is a potential footgun. Options:

- Document clearly in the protocol's doc comment
- Add a warning diagnostic in the macro
- Accept the current behavior — real models should all use `@Syncable`

### 4. Overload 1 (`Related: PersistentModel`, not `SyncModelable`) cannot call `syncMarkChanged()`

If `Owner` is not constrained to `SyncUpdatableModel` in Overload 1, any caller landing there would
silently not dirty the owning row. If Overload 1 has no real callers, consider removing it.
