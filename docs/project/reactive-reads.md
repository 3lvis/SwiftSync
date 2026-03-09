# Reactive Reads

SwiftSync has three reactive local read APIs:

- `@SyncQuery` for SwiftUI list reads
- `@SyncModel` for SwiftUI detail reads by sync ID
- `SyncQueryPublisher` for UIKit and non-SwiftUI flows

All three read from local `SwiftData` (`syncContainer.mainContext`). They do not call the network by themselves.

## User-facing mental model

Think of `@SyncQuery` as:

- "Keep this list in sync with local storage using this filter and this sort order."

Think of `@SyncModel` as:

- "Keep this single model (by sync ID) refreshed for UI rendering."

Reactive reads are query-snapshot driven. They are not retained-object live merge semantics.

## Query shapes

`@SyncQuery` and `SyncQueryPublisher` support the same fetch shapes:

1. Full fetch (optionally sorted)
2. Predicate-based fetch (`predicate:`)
3. Relationship-scoped fetch (`relationship:` + `relationshipID:`)

Relationship-scoped example (tasks for one project):

```swift
@SyncQuery(
  Task.self,
  relationship: \Task.project,
  relationshipID: projectID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.updatedAt, order: .reverse)]
)
var tasks: [Task]
```

Predicate example (business filter):

```swift
@SyncQuery(
  Task.self,
  predicate: #Predicate<Task> { $0.isArchived == false },
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.priority, order: .reverse),
    SortDescriptor(\Task.updatedAt, order: .reverse)
  ]
)
var activeTasks: [Task]
```

## Relationship path rules

SwiftSync uses explicit relationship paths for relationship-scoped queries:

- pass `relationship:` and `relationshipID:` together
- to-one and to-many relationship key paths are both supported
- keep the path explicit when a model has multiple relationships to the same related type

Example (multiple `User` relationships on `Task`):

- `Task.assignee`
- `Task.reviewer`
- `Task.watchers`

Use the intended path directly:

```swift
@SyncQuery(
  Task.self,
  relationship: \Task.assignee,
  relationshipID: userID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.updatedAt, order: .reverse)]
)
var assignedTasks: [Task]
```

## `sortBy` vs `refreshOn`

- `sortBy:` controls result ordering
- `refreshOn:` expands invalidation to related model changes used by the screen

Example:

```swift
@SyncQuery(
  Task.self,
  relationship: \Task.assignee,
  relationshipID: userID,
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.priority, order: .reverse),
    SortDescriptor(\Task.updatedAt, order: .reverse)
  ],
  refreshOn: [\.project]
)
var tasks: [Task]
```

Mental model for `refreshOn: [\.project]`:

- "Reload this task query if a related project changes because this UI reads project fields."

## How updates reach UI

High-level flow:

1. Sync writes happen in a background context.
2. `SyncContainer` observes saves and computes changed type/ID metadata.
3. Reactive wrappers invalidate and refetch when those changes are relevant.
4. SwiftUI/UIKit renders fresh snapshots from the local store.

This is the intended "sync and forget" path: sync updates local data and reactive reads update UI.

## App usage conventions

These conventions keep app-level behavior predictable:

- treat views as reactive local readers (`@SyncQuery` / `@SyncModel`)
- put backend mutation and sync orchestration in a domain/service layer
- pass IDs/scalars between views and let each view own its own query
- avoid passing long-lived `SwiftData` model references through navigation flows

Typical save flow:

1. Detail view opens a modal with IDs/scalars.
2. Modal submits a save intent.
3. Domain layer performs backend mutation and sync.
4. UI re-renders from local store updates.

## UIKit usage (`SyncQueryPublisher`)

Use `SyncQueryPublisher` as the Combine equivalent of `@SyncQuery`:

```swift
let publisher = SyncQueryPublisher(
  Project.self,
  in: syncContainer,
  sortBy: [SortDescriptor(\Project.name)]
)

publisher.$rows
  .receive(on: DispatchQueue.main)
  .sink { [weak self] rows in self?.applySnapshot(rows) }
  .store(in: &cancellables)
```

It supports the same query shapes (full/predicate/relationship-scoped) and reacts to the same save invalidation path as `@SyncQuery`.

## Design rationale and tradeoffs

### Goal

Provide practical reactive reads with minimal app-side invalidation plumbing:

- sync writes local data
- UI re-renders from local query snapshots
- app code stays convention-first

### Why this direction

SwiftData gives strong fetch/save primitives and change notifications, but not full FRC-style list diff callbacks. SwiftSync therefore favors query-driven invalidation and refetch over retained-object live merge behavior.

### Current tradeoff

Pros:

- simple API surface
- fits SwiftUI well
- predictable "local source of truth" behavior

Tradeoffs:

- no FRC-style granular diff callback contract
- refetch precision depends on invalidation heuristics and `refreshOn`
