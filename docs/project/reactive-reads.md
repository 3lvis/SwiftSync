# Reactive Reads

SwiftUI is the primary integration path. UIKit is supported via `SyncQueryPublisher` for cases where SwiftUI is not available.

This document explains both:

- the user-facing mental model for SwiftSync reactive reads
- the design rationale/tradeoffs behind the current reactive read approach

## User-Facing Mental Model / Usage

## What `@SyncQuery` / `@SyncModel` are

They are reactive local read helpers.

- `@SyncQuery` keeps an array updated with rows from the local `SyncContainer` that match a rule.
- `@SyncModel` keeps one local model (looked up by sync ID) refreshed for UI use.

They do not call the network by themselves.

## Mental Model

Think of `@SyncQuery` as:

- "Keep this list in sync with local storage, using this filter and sort order."

Three common query shapes:

1. `relatedTo:` + `relatedID:` (relationship-scoped query by ID)
- Example: all `Task` rows that belong to a specific `Project` ID.

```swift
@SyncQuery(
  Task.self,
  relatedTo: Project.self,
  relatedID: projectID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.updatedAt, order: .reverse)]
)
var tasks: [Task]
```

2. `predicate:` (custom business filters)
- Use for scalar-only filters, compound filters, or non-relationship business filters.

## Inference Rules (`relatedTo:` / `relatedID:`)

SwiftSync infers the relationship automatically when exactly one matching relationship exists on the queried model for the related type.

- exactly 1 candidate => inferred
- 0 candidates => fail fast
- more than 1 candidate (or both to-one and to-many candidates) => pass `through:` explicitly

Example (ambiguous relationship):

```swift
@SyncQuery(
  Ticket.self,
  relatedTo: User.self,
  relatedID: userID,
  through: \Ticket.assignee,
  in: syncContainer,
  sortBy: [SortDescriptor(\Ticket.id)]
)
var assignedTickets: [Ticket]
```

Example (same queried model + same related model, multiple paths):
- `Task.assignee` (`User?`)
- `Task.reviewer` (`User?`)
- `Task.watchers` (`[User]`)
- `@SyncQuery(Task.self, relatedTo: User.self, relatedID: userID, ...)` is ambiguous, so pass explicit `through:` for each path.

Related modeling note:
- relationship-scoped queries assume the local relationship graph is trustworthy
- for many-to-many relationships, ensure the pair has one explicit inverse anchor (`@Relationship(inverse: ...)`) and see `docs/project/relationship-integrity.md` for the corrected rule

## `sortBy` vs `refreshOn`

- `sortBy:` defines order.
- `refreshOn:` expands which related model changes should invalidate/refetch the query.

Example:

```swift
@SyncQuery(
  Task.self,
  relatedTo: User.self,
  relatedID: userID,
  through: \Task.assignee,
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.priority, order: .reverse),
    SortDescriptor(\Task.id)
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

These are application-layer conventions that work well with the reactive read model.

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

## UIKit: SyncQueryPublisher

For UIKit screens, use `SyncQueryPublisher` — the Combine-backed equivalent of `@SyncQuery`.

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

It supports the same query shapes as `@SyncQuery`:
- plain fetch with optional predicate
- `relatedTo:` + `through:` for relationship-scoped queries

It reacts to the same internal save notifications as `@SyncQuery` and applies the same reload heuristics (`changedTypeNames`, `changedIDs`).

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
