# Parent Scope Follow-up

This document tracks what we removed now, and what still cannot be removed safely yet.

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
