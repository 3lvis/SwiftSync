# Parent Scope Follow-up

This document explains current parent-scope behavior after the inference update.

## TL;DR

Parent sync has two responsibilities:
1. Attach child rows to the provided parent.
2. Scope diff/delete to only that parent's children.

SwiftSync now supports both styles:
- inferred parent relationship by default when exactly one candidate exists
- explicit `parentRelationship` when relationship choice is ambiguous

## Current Behavior

When you call:

```swift
try await SwiftSync.sync(
  payload: payload,
  as: Child.self,
  in: context,
  parent: parentObject
)
```

SwiftSync resolves the child->parent relationship using this rule:
1. Find to-one relationships on `Child` that match the runtime parent type.
2. If exactly 1 exists: use it automatically.
3. If 0 exist: throw a typed `invalidPayload` error.
4. If more than 1 exist: throw a typed `invalidPayload` error listing candidates.

No fallback guessing is used for ambiguous cases.

## Why This Matters

With `missingRowPolicy: .delete`, parent sync must compute:

```text
toDelete = (rows belonging to this parent scope) - (payload identities)
```

If scope resolution is wrong, delete can target valid rows from another logical scope.

## Minimal Real-World Scenario

### Case A: Single relationship (inference succeeds)

Models:

```swift
@Model final class Task {
  @Attribute(.unique) var id: Int
  var title: String
  @Relationship(inverse: \Comment.task) var comments: [Comment]
}

@Model final class Comment {
  @Attribute(.unique) var id: Int
  var text: String
  var task: Task?
}
```

There is exactly one `Comment -> Task?` relationship (`task`), so default parent inference resolves it automatically.

### Case B: Multiple relationships (explicit key path required)

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
SwiftSync throws and asks for explicit configuration:

```swift
extension Ticket: ParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Ticket, User?> { \.assignee }
}
```

## Identity Policy Notes

- `ParentScopedModel` defaults to `.scopedByParent`.
- Inferred parent sync (no `ParentScopedModel` conformance) defaults to `.global`.
- If inferred sync should allow duplicate child IDs across different parents, pass:

```swift
identityPolicy: .scopedByParent
```

## What Was Removed vs Kept

Removed for unambiguous models:
- mandatory explicit `parentRelationship`

Still required for ambiguous models:
- explicit `parentRelationship` (deterministic scope selection)

## Safety Contract

SwiftSync does not silently guess between multiple candidate parent relationships.
Ambiguity is surfaced as an error to avoid cross-scope delete mistakes.
