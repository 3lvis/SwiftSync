# Reactive Reads

Read this document when you want the UI side of SwiftSync to feel simple.

Short version:
- use `@SyncQuery` for reactive local lists
- use `@SyncModel` for one reactive local row by ID
- use `SyncQueryPublisher` / `SyncModelPublisher` when you are not in SwiftUI
- keep the network and mutation logic outside the view; let the UI react to local store updates

SwiftUI is the primary integration path. UIKit is supported via `SyncQueryPublisher` when SwiftUI is not available.

This doc explains:
- what to use first
- the common query shapes
- how to structure save flows so the UI stays simple
- the rationale behind the current reactive-read model

## What To Use

Pick the smallest tool that matches the screen:

- `@SyncQuery`: a reactive local list
- `@SyncModel`: one reactive local row by sync ID
- `SyncQueryPublisher`: a non-SwiftUI reactive list
- `SyncModelPublisher`: a non-SwiftUI reactive single-row read

They do not call the network by themselves.

## Quick Mental Model

Think of SwiftSync reads like this:

- sync writes data into the local store
- the UI reads from the local store
- reactive read helpers keep the UI fresh when relevant local data changes

In practice, `@SyncQuery` means:
- "Keep this list in sync with local storage, using this filter and sort order."

## Common Query Shapes

Use one of these three patterns first:

1. `relationship:` + `relationshipID:`
   For relationship-scoped screens, like tasks for a project.
2. `predicate:`
   For scalar-only filters or compound business filters.
3. plain fetch with `sortBy:`
   For screens that show all rows of a model type.

## `@SyncQuery` / `@SyncModel`

- `@SyncQuery` keeps an array updated with rows from the local `SyncContainer` that match a rule.
- `@SyncModel` keeps one local model (looked up by sync ID) refreshed for UI use.

## Mental Model

Three common query shapes:

1. `relationship:` + `relationshipID:` (relationship-scoped query by ID)
- Example: all `Task` rows that belong to a specific `Project` ID.

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

2. `predicate:` (custom business filters)
- Use for scalar-only filters, compound filters, or non-relationship business filters.

3. plain fetch (optionally sorted)
- Use when the screen needs all rows of a model type and only local ordering/filter defaults.

## Relationship Path Rules (`relationship:` / `relationshipID:`)

SwiftSync requires an explicit relationship key path for relationship-scoped queries.

- pass `relationship:` for every relationship-scoped query
- to-one and to-many are both supported via typed key paths

Example (ambiguous relationship):

```swift
@SyncQuery(
  Ticket.self,
  relationship: \Ticket.assignee,
  relationshipID: userID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Ticket.updatedAt, order: .reverse)]
)
var assignedTickets: [Ticket]
```

Example (same queried model + same related model, multiple paths):
- `Task.assignee` (`User?`)
- `Task.reviewer` (`User?`)
- `Task.watchers` (`[User]`)
- `@SyncQuery(Task.self, relationship: ..., relationshipID: userID, ...)` stays explicit for each path.

Related modeling note:
- relationship-scoped queries assume the local relationship graph is trustworthy
- for many-to-many relationships, ensure the pair has one explicit inverse anchor (`@Relationship(inverse: ...)`) and see `docs/project/relationship-integrity.md` for the corrected rule

## `sortBy` vs `refreshOn`

- `sortBy:` defines order.
- `refreshOn:` expands which related model changes should invalidate/refetch the query.
- `sortBy:` does not change invalidation scope.

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
- "Also refresh this query if a task's related project changes, because the UI reads project data."

## How UI Updates Happen

High level flow:

1. Sync writes happen in a background context.
2. `SyncContainer` observes saves and tracks changed IDs/types.
3. `@SyncQuery` / `@SyncModel` invalidate and refetch when relevant changes happen.
4. SwiftUI re-renders using fresh local snapshots.

This is the "sync and forget" experience: sync updates local storage, and reactive reads update UI.

## App Best Practices (SwiftUI + SwiftData + SwiftSync)

Use these rules if you want SwiftSync to stay predictable as screens get more complex.

## Views React, Domain Layer Persists

Treat SwiftUI views as reactive readers of local state.

- views read from `@SyncQuery` / `@SyncModel`
- views render UI and collect user intent
- views should not own persistence or sync orchestration logic

Put persistence + sync behavior in a domain/service layer (for example, a `syncEngine`).

- domain layer performs backend mutations
- domain layer syncs refreshed backend data into local storage
- views update automatically from local reactive reads

## Pass IDs/Scalars, Not SwiftData Model Objects

Default rule for navigation destinations, sheets, and modals:

- pass scalar IDs and simple values (`String`, enums, booleans, etc.)
- child view queries/owns the models it needs
- avoid passing SwiftData model objects across view boundaries

Why:

- it keeps data ownership local to the view
- it avoids stale retained model-reference assumptions
- it makes modal/detail flows easier to reason about and test

Render-only leaf subviews may take scalar display values derived by the parent (`title`, `status`, `count`, etc.) instead of full models.

## Save Flow (Detail -> Modal -> Sync)

Recommended flow for edit sheets/modals:

1. Detail view presents modal and passes IDs/scalars.
2. Modal owns form draft state and submits "save" intent.
3. Domain layer performs backend mutation + targeted sync.
4. Detail view re-renders from local store changes.

Practical rule:

- modal initiates save intent
- domain layer performs save/sync
- detail view reacts; it does not manually re-fetch the backend

## Reload Source of Truth After Save

UI should refresh from the local store, not directly from the backend response path in the view.

- local SwiftData store is the UI read source of truth
- backend remains authoritative for mutation confirmation
- domain layer decides sync strategy (targeted re-fetch, response-driven sync, optimistic write + reconciliation)

The key invariant is stable: views read local reactive state; the domain layer keeps that local state current.

## UIKit / State Machines

If you are not using SwiftUI, use the Observation-based publishers instead of trying to recreate your own reactive bridge:

- `SyncQueryPublisher` for lists via reactive `rows`
- `SyncModelPublisher` for a single row via reactive `row`

```swift
import Observation

final class ProjectsViewController: UIViewController {
    private var projectsObserver: SyncQueryPublisher<Project>?

    func bindProjects() {
        let observer = SyncQueryPublisher(
            Project.self,
            in: syncContainer,
            sortBy: [SortDescriptor(\Project.name)]
        )
        projectsObserver = observer

        func track() {
            withObservationTracking {
                applySnapshot(observer.rows)
            } onChange: {
                Task { @MainActor in track() }
            }
        }

        track()
    }
}
```

Single-row detail/state-machine example:

```swift
final class TaskDetailMachine {
    private let taskPublisher: SyncModelPublisher<Task>

    init(taskID: String, syncContainer: SyncContainer) {
        self.taskPublisher = SyncModelPublisher(
            Task.self,
            id: taskID,
            in: syncContainer
        )
    }
}
```

Recommended machine shape for synced detail screens:

- let the screen machine own the reactive publishers and load/submission orchestration
- expose live reads from those publishers through thin computed properties on the machine
- keep lightweight display-specific derivations there when they are part of the screen contract, such as sorted reviewer or watcher names
- do not retain a separate same-identity snapshot of the synced model inside the machine just to reshape it for the view

Why this shape works:

- the machine boundary stays consistent with the rest of the app
- the view can remain mostly declarative without taking on sync orchestration
- the machine avoids introducing another cache layer that can go stale across same-identity updates

Applied to a task-detail style screen, prefer this shape:

```swift
@MainActor
@Observable
final class TaskDetailMachine {
    private let taskPublisher: SyncModelPublisher<Task>
    private let itemPublisher: SyncQueryPublisher<Item>
    private let loadMachine: ScreenLoadMachine

    var task: Task? { taskPublisher.row }
    var items: [Item] { itemPublisher.rows }
    var reviewerNames: [String] { task?.reviewers.map(\.displayName).sorted() ?? [] }
}
```

Avoid this shape:

- storing a separate `TaskDetailViewState` or similar retained snapshot that mirrors `taskPublisher.row`
- copying publisher output into another long-lived same-identity value unless that extra state represents a real UI contract that cannot be derived safely on read
`SyncQueryPublisher` supports the same query shapes as `@SyncQuery`:
- plain fetch with optional predicate
- `relationship:` + `relationshipID:` for relationship-scoped queries

`SyncModelPublisher` matches the single-row contract of `@SyncModel`: observe one row by sync identity and rebind when that row changes.

Both publishers react to the same internal save notifications as `@SyncQuery` / `@SyncModel` and reload from the local store after relevant sync-driven save notifications.

Hold it as a property — it starts observing on init and stops on deinit.

## Design Rationale / Tradeoffs

This section keeps the key design reasoning in one place so users and maintainers can understand why the reactive APIs look the way they do.

## Goal

Provide a practical "sync and forget" experience for SwiftUI apps:

- background sync writes local data
- UI updates automatically from local reads
- minimal app-level invalidation plumbing

## Current Constraints and Observations

### What SwiftSync already has

- `SyncContainer` with main/background context separation
- save observation and changed-ID processing
- reliable background sync execution/cancellation behavior

### Observed behavior (important)

- fresh main-context fetches can see background writes
- long-lived retained model references can still become stale

Implication:
- reactive UI should be query-snapshot driven, not retained-object-reference driven

## SwiftData Constraints (Why not FRC semantics)

SwiftData gives us useful primitives (`fetch`, `save`, save notifications, changed identifiers), but not a full FRC-style list-change contract.

What it does not give us here:

- automatic in-place refresh of all retained model references across contexts
- an FRC-style granular insert/update/delete callback contract
- ordered to-many sync semantics needed by this pipeline

So SwiftSync favors query-driven reactive reads instead of trying to recreate FRC behavior.

## Candidate Approaches Considered

### A) Query-Driven Read Layer + Sync Events (Current Direction)

Principle:
- UI renders from query snapshots (`@SyncQuery`, `@SyncModel`)
- sync writes trigger invalidation/refetch via `SyncContainer`

Pros:
- smallest custom infrastructure
- aligns with SwiftUI + SwiftData
- easy to reason about and document

Tradeoffs:
- not object-reference live-merge semantics
- refetch precision depends on invalidation heuristics and `refreshOn`

### B) Observable Query Store Layer (Future Option)

Principle:
- internal query registry owns descriptors + cached snapshots and invalidation

Pros:
- more targeted invalidation
- may scale better for larger apps

Tradeoffs:
- more framework complexity and maintenance

### C) FRC-Style Diff Engine (Avoid Unless Required)

Pros:
- closest to legacy FRC behavior
- richer non-SwiftUI callback possibilities

Tradeoffs:
- highest complexity
- easy to introduce subtle bugs
- duplicates work SwiftUI already handles with identity-based list diffs

## Why A Is the Default Choice

It gives the best balance of:

- reliability
- API simplicity
- maintainability
- alignment with SwiftUI

Core convention:
- treat query wrappers as the UI source of truth
- avoid relying on retained model instances staying fresh automatically

## Current Limitations / Non-Goals

- SwiftSync does not try to provide FRC-style granular diff callbacks.
- Reactive read wrappers are the primary intended SwiftUI integration path.
- Ordered to-many sync semantics are not part of this reactive read design.

## Revisit Triggers (When to Reconsider the Design)

Revisit the architecture if we repeatedly see:

- performance issues from broad refetches
- invalidation precision problems affecting UX
- real demand for non-SwiftUI granular change callbacks

## Open Questions

1. Should `SyncContainer` expose a public publisher/stream for changed IDs/types, or keep invalidation wrapper-internal?
2. Should we expose a stricter detail-view refresh mode as an opt-in?
3. What metrics/logging would best reveal over-refetching before adding a query registry?
