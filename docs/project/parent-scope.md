# Parent-Scoped Sync and Query Behavior

Read this when an endpoint only returns children for one parent, such as `/projects/{id}/tasks` or `/users/{id}/notes`.

The core rule is simple:
- parent-scoped sync always uses an explicit `relationship:` key path
- relationship-scoped reads always use an explicit `relationship:` + `relationshipID:`

SwiftSync does not infer parent scope for you.

## TL;DR

Parent sync has two responsibilities:
1. Attach child rows to the provided parent.
2. Scope diff/delete to only that parent's children.

SwiftSync uses explicit parent relationships for parent-scoped sync.

Reactive reads always use explicit relationship paths:
- `@SyncQuery(..., relationship: \.relationship, relationshipID: parentID, ...)`

## Current Behavior

When you call:

```swift
try await SwiftSync.sync(
  payload: payload,
  as: Child.self,
  in: context,
  parent: parentObject,
  relationship: \Child.parent
)
```

SwiftSync uses the provided `relationship` key path directly; no relationship inference is performed.

## Why This Matters

Parent sync computes deletions scoped to the parent:

```text
toDelete = (rows belonging to this parent scope) - (payload identities)
```

If scope resolution is wrong, delete can target valid rows from another logical scope.

That is why the API is explicit here instead of "helpfully" guessing.

## Minimal Real-World Scenario

### Case A: Single relationship (explicit key path)

Models:

```swift
@Model final class Project {
  @Attribute(.unique) var id: Int
  var name: String
  @Relationship(inverse: \Task.project) var tasks: [Task]
}

@Model final class Task {
  @Attribute(.unique) var id: Int
  var title: String
  var project: Project?
}
```

Pass `relationship: \Task.project` when syncing tasks for a project parent scope.

### Case B: Multiple relationships (choose explicit path)

Models:

```swift
@Model final class User {
  @Attribute(.unique) var id: Int
  var name: String
}

@Model final class Ticket {
  @Attribute(.unique) var id: Int
  var title: String
  var assignee: User?
  var reviewer: User?
}
```

If parent passed is a `User`, both `assignee` and `reviewer` are valid candidates.
Choose the intended path explicitly at call sites:

```swift
try await SwiftSync.sync(
  payload: payload,
  as: Ticket.self,
  in: context,
  parent: user,
  relationship: \Ticket.assignee
)
```

## Safety Contract

SwiftSync does not guess parent relationships. Call sites must declare scope explicitly via `relationship:`.

## To-One Query Example

```swift
@SyncQuery(
  Task.self,
  relationship: \Task.project,
  relationshipID: projectID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.id)]
)
var tasks: [Task]
```

Ambiguous example:

```swift
@SyncQuery(
  Ticket.self,
  relationship: \Ticket.assignee,
  relationshipID: userID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Ticket.id)]
)
var assignedTickets: [Ticket]
```
