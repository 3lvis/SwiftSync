# Parent Scope Follow-up

This document tracks what we removed now, and what still cannot be removed safely yet.

## Simple Explanation

`parentRelationship` is the one line that tells SwiftSync:
- where to attach a child to its parent
- which rows belong to the current parent scope for diff/delete

Without that line, parent-scoped `.delete` can accidentally affect the wrong rows.

## What We Reduced

Current usage can be as small as:

```swift
extension Task: GlobalParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Task, Project?> { \.project }
}
```

No `typealias SyncParent` and no explicit `syncIdentityPolicy` override are required.

## What Still Cannot Be Removed Safely

`parentRelationship` is still required.

Why:
- parent-scoped sync needs an explicit writable key path to scope delete/diff safely
- parent assignment on insert/update needs a concrete relationship key path
- ambiguous relationship graphs cannot be resolved safely by guessing

If we infer this incorrectly, parent-scoped `.delete` can target wrong rows.

## How Old Sync Handled This

Old Core Data Sync did not require a typed key path from app code. It used entity metadata at runtime to find a relation from child entity to parent entity, then picked the first match.

Behavior summary:
1. Find relationships where `destinationEntity == parentEntity`.
2. Pick `.first` relationship as parent link.
3. Build predicate with that relationship for scoped diff/delete.

Why this was risky:
1. Multiple matching relationships were ambiguous (`.first` depended on model ordering).
2. If no relationship was found, scoped sync could degrade toward unscoped behavior.
3. Ambiguity was not surfaced as a typed error.

SwiftSync intentionally avoids that implicit behavior by requiring `parentRelationship`.
This keeps parent scope deterministic and prevents silent data loss.

## Practical Example

If `Task` has both:
- `project` (ownership)
- `reviewProject` (secondary link)

and we guessed the wrong one:
1. Sync could attach rows to the wrong parent field.
2. Scoped delete could remove rows that belong to another logical scope.

Declaring:

```swift
extension Task: GlobalParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Task, Project?> { \.project }
}
```

eliminates that ambiguity.

## Edge Cases Blocking Full Inference

1. Multiple to-one relationships from child to same parent type.
2. No relationship from child to passed parent type.
3. Self-referential trees and supertype-compatible relations.
4. Parent scope plus caller predicate composition rules.

## Future Work (No New Macros Required)

1. Add runtime inference helper for parent relationship:
- infer only if exactly one candidate relationship exists
- fail with typed error on 0 or >1 candidates

2. Add strict guardrails in parent sync path:
- hard-fail if parent scope cannot be resolved
- never allow scope-less parent delete path
- combine parent scope and caller predicate explicitly

3. Keep explicit escape hatch for ambiguous cases:
- continue allowing explicit `parentRelationship` declaration

## Goal

Convention-first path for common models, explicit path only for ambiguous models,
without silent data corruption risk.
