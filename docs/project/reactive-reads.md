# Reactive Reads (SwiftData + SwiftUI)

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

1. `toOne:` (belongs-to / ownership)
- Example: all `Comment` rows that belong to a specific `Task`.

```swift
@SyncQuery(
  Comment.self,
  toOne: task,
  in: syncContainer,
  sortBy: [SortDescriptor(\Comment.createdAt, order: .reverse)]
)
var comments: [Comment]
```

2. `toMany:` (membership / contains)
- Example: all `Tag` rows that include a specific `Task` in their `tasks` relationship.

```swift
@SyncQuery(
  Tag.self,
  toMany: task,
  in: syncContainer,
  sortBy: [SortDescriptor(\Tag.name)]
)
var tags: [Tag]
```

3. `predicate:` (custom business filters)
- Use for scalar-only filters, compound filters, or cases where you do not have the related model instance.

## Inference Rules (`toOne:` / `toMany:`)

SwiftSync infers the relationship automatically when exactly one matching relationship exists on the queried model.

- exactly 1 candidate => inferred
- 0 candidates => fail fast
- more than 1 candidate => pass `via:` explicitly

Example (ambiguous to-one):

```swift
@SyncQuery(
  Ticket.self,
  toOne: user,
  via: \.assignee,
  in: syncContainer,
  sortBy: [SortDescriptor(\Ticket.id)]
)
var assignedTickets: [Ticket]
```

## `sortBy` vs `refreshOn`

- `sortBy:` defines order.
- `refreshOn:` expands which related model changes should invalidate/refetch the query.

Example:

```swift
@SyncQuery(
  Task.self,
  toOne: user,
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
