# SwiftSync FAQ (Advanced)

This document captures the current design decisions that go beyond the quick FAQ in `README.md`.

## 1) Parent-scoped identity vs global identity

`ParentScopedModel` defaults to:
- `syncIdentityPolicy = .scopedByParent`

Meaning:
- identity is treated as `(parent, remoteID)` during parent-scoped sync
- two different parents can have child rows with the same remote `id`

If you want global identity instead, override:

```swift
extension Child {
  static var syncIdentityPolicy: SyncIdentityPolicy { .global }
}
```

Important:
- `@Attribute(.unique)` on raw `id` is a SwiftData store-level global uniqueness rule.
- If you set that on a scoped entity, global uniqueness wins and scoped duplicates are not possible.

## 2) Foreign-key (`*_id`) typing policy

Relationship FK lookup is strict by type:
- `Int` FK links to `Int` identity
- `String` FK links to `String` identity
- no automatic cross-type coercion at relationship-link step

This is intentional to avoid ambiguous linking.  
Scalar attributes still support coercion paths where appropriate.

`@Syncable` auto-generates this helper behavior for common relationship patterns:
- to-one by `*_id`
- to-many by `*_ids`

Use a tiny `SyncRelationshipUpdatableModel` wrapper to call `syncApplyGeneratedRelationships(...)`.
For nested object payload relationships or custom merge policies, keep manual custom implementations.

## 3) Ordered to-many parity

When relationship metadata is ordered, SwiftSync should preserve remote order semantics.  
When unordered, membership semantics are set-based.

## 4) Relationship operation flags

Sync calls expose per-call relationship operation control:

```swift
try await SwiftSync.sync(
  payload: payload,
  as: Model.self,
  in: context,
  relationshipOperations: [.insert, .update]
)
```

Defaults:
- `.all` (insert + update + delete)

Use this to run root-row sync while narrowing relationship-side work for a specific pass.

## 5) Missing-row policy

`missingRowPolicy` controls what happens to local rows not present in payload:
- `.delete` (default): payload is authoritative for that scope
- `.keep`: do not delete missing local rows

For parent-scoped sync, delete behavior is scoped to that parent subset.
