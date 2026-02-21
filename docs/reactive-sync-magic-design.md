# Reactive Sync Magic Design (SwiftData + SwiftUI)

## Goal

Define a practical path to the old "sync and forget" developer experience:

- call sync in background
- UI updates automatically
- minimal app-level plumbing
- convention-first defaults (Rails-like)

## Scope (Current Iteration)

- SwiftUI-only for now.
- Target APIs are `@SyncQuery` and `@SyncModel` for reactive reads.
- UIKit/non-SwiftUI integration is explicitly out of scope for this document.

## Desired Behavior

### DX target

1. Developer calls one sync API.
2. Main UI state updates without manual screen-by-screen refresh code.
3. Lists animate inserts/updates/deletes naturally.
4. Detail views avoid stale data surprises.

### Behavioral target

- Background writes become visible in main read path predictably.
- Main read path is reactive by default.
- Identity-driven diffing keeps UI stable and animated.

## How It Used To Work (Core Data + FRC)

Typical legacy setup:

1. Background context performs writes.
2. Background `save()` emits context-save notifications.
3. Main context merges those changes.
4. `NSFetchedResultsController` observes managed object changes and emits granular list updates.
5. UITableView/UICollectionView apply animated diffs via delegate callbacks.

Result: "sync and forget" felt automatic.

## Current State in This Repo

### What we already have

- Strong sync conventions/macros (`@Syncable`, `@PrimaryKey` defaults).
- Background sync reliability/cancellation work.
- `SyncContainer` wrapper with:
  - `mainContext`
  - `makeBackgroundContext()`
  - `ModelContext.didSave` observation
  - change-ID processing + `processPendingChanges()`

### Observed behavior (tests)

- Fresh fetches in main context see background updates.
- Retained main-context object references can still be stale.

Relevant tests:

- `testBackgroundWriteNotVisibleToMainReadWithoutRefreshPolicy`
- `testSyncContainerBackgroundSaveVisibilityBehavior`

### Current sync policy decisions implemented

- Identity policy is explicit per model:
  - `SyncModelable` default: `.global`
  - `ParentScopedModel` default: `.scopedByParent`
- Parent-scoped sync delete/diff stays inside the parent scope.
- Relationship work can be controlled per call with `relationshipOperations` (`.insert`, `.update`, `.delete`, `.all`).
- FK relationship lookup is strict by type (no cross-type coercion at relationship link step).
- Store-level uniqueness (`@Attribute(.unique)`) can still enforce global uniqueness regardless of scoped identity intent.

## SwiftData Primitives We Can Piggyback On

- `ModelContainer.mainContext`
- `ModelContext.didSave` / `willSave`
- Notification keys:
  - `insertedIdentifiers`
  - `updatedIdentifiers`
  - `deletedIdentifiers`
- Standard context ops:
  - `fetch`
  - `save`
  - `rollback`
  - `processPendingChanges`

## Gap vs FRC

What SwiftData + current wrapper does not yet guarantee:

- automatic in-place refresh of already-retained model instances across contexts
- FRC-style granular change callback contract out of the box
- ordered to-many relationship sync semantics (SwiftData metadata/API does not expose the needed ordered relationship mode here)

So we need a read-layer convention that is reactive-by-default.

## Candidate Paths

## Path A (Recommended): Query-Driven Read Layer + Sync Events

Principle:

- Never treat retained model references as the UI source of truth.
- UI renders from query snapshots (fresh fetches / `@Query` / `@SyncQuery` / `@SyncModel`).

Flow:

1. Sync writes in background context.
2. `SyncContainer` publishes changed IDs.
3. SwiftUI read scopes requery relevant data.
4. SwiftUI diffs collections by stable IDs and animates updates.

Pros:

- Minimal custom infrastructure.
- Aligns with SwiftData + SwiftUI model.
- Keeps "magic" mostly convention-based.

Tradeoff:

- Not object-reference live merge semantics like old FRC internals.

## Path B: Observable Query Store Layer

Principle:

- Build a tiny repository layer that owns query subscriptions and emits snapshots.

Flow:

1. Register query descriptors with keys (e.g. `users.list`, `user.detail.<id>`).
2. On changed IDs, invalidate only affected query keys.
3. Recompute snapshots and publish to UI.

Pros:

- More targeted than full-screen refresh.
- Better scaling for large apps.

Tradeoff:

- More internal framework code.

## Path C: FRC-Style Diff Engine (Most Complex)

Principle:

- Build explicit insert/update/delete/move diff output from snapshots.

Pros:

- Closest to FRC delegate semantics.

Tradeoff:

- Highest complexity and maintenance cost.
- Reinvents part of what SwiftUI can already do with identity-based list diffing.

## Recommended Iteration Plan

1. Standardize `SyncContainer` API and changed-ID event publishing.
2. Adopt Path A conventions in one pilot feature (Users list + User detail).
3. Add docs and templates so usage is default, not optional.
4. If scaling pain appears, evolve to Path B.
5. Only consider Path C if specific product requirements need granular diff callbacks.

## Proposed `SyncContainer` Direction

Minimum surface:

- `mainContext`
- `makeBackgroundContext()`
- `sync(...)` helper (optional convenience)
- `didSaveChanges` publisher/callback with changed IDs

Conventions:

- List screens: always query-driven.
- Detail screens: bind by ID and requery on change/invalidation.
- Avoid long-lived retained model objects as the sole UI truth source.

## Best Magical API (Proposed)

Design goals:

- feels like `ModelContainer`
- one obvious way to sync
- one obvious way to read reactively
- minimal manual invalidation code

### Container setup

```swift
let syncContainer = try SyncContainer(
  for: User.self, Note.self,
  configurations: .init(url: storeURL)
)
```

### Sync (fire-and-forget style with safe defaults)

```swift
try await syncContainer.sync(
  payload: usersPayload,
  as: User.self,
  missingRowPolicy: .delete,
  relationshipOperations: .all
)
```

Parent-scoped:

```swift
try await syncContainer.sync(
  payload: notesPayload,
  as: Note.self,
  parent: user,
  missingRowPolicy: .delete,
  relationshipOperations: .all
)
```

### Reactive reads (SwiftUI-facing)

```swift
@SyncQuery(User.self, in: syncContainer, sortBy: [\.id])
var users: [User]
```

Descending or mixed ordering still uses explicit `SortDescriptor` values:

```swift
@SyncQuery(
  Task.self,
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.priority, order: .reverse),
    SortDescriptor(\Task.id)
  ]
)
var tasks: [Task]
```

Detail:

```swift
@SyncModel(User.self, id: userID, in: syncContainer)
var user: User?
```

### What the magic does

1. Writes always happen in a background context owned by `SyncContainer`.
2. Save notifications are observed internally.
3. Changed IDs invalidate registered read scopes.
4. `@SyncQuery` / `@SyncModel` transparently refetch on invalidation.
5. SwiftUI handles identity-based list diffs/animations.

### Why this is the best "magic" target

- Keeps app code close to "sync and forget."
- Uses SwiftData primitives instead of replacing the stack.
- Preserves convention-first style already used by `@Syncable` and `@PrimaryKey`.

## Acceptance Criteria

1. Calling sync updates list UI without manual per-screen refresh code.
2. Background sync + main UI list produces stable animated diffs by ID.
3. Detail screen stale-data behavior is deterministic and documented.
4. No regressions in current sync reliability/cancellation tests.

## Open Questions

1. Do we want a Combine/Observation publisher API in `SyncContainer`, or keep wrapper-driven invalidation only for SwiftUI?
2. Should `SyncContainer` expose changed model types in addition to changed IDs?
3. Do we want an opt-in strict mode that forces detail requery by ID after any background save?
