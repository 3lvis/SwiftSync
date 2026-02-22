# Reactive Reads (SwiftData + SwiftUI)

This document explains the user-facing mental model for SwiftSync reactive reads.

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
