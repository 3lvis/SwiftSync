# SwiftSync FAQ (Advanced)

This document captures the current design decisions that go beyond the quick FAQ in `README.md`.

Backend payload contract guidance lives in `docs/backend-contract.md`.
Parent-scope boilerplate follow-up is tracked in `docs/parent-scope-follow-up.md`.

## 1) Parent-scoped identity vs global identity

`ParentScopedModel` defaults to:
- `syncIdentityPolicy = .scopedByParent`

Meaning:
- identity is treated as `(parent, remoteID)` during parent-scoped sync
- two different parents can have child rows with the same remote `id`

If you want global identity instead, override:

```swift
extension Child: GlobalParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Child, Parent?> { \.parent }
}
```

If you do not conform to `ParentScopedModel`, parent sync can still work through runtime relationship inference:
- if exactly one to-one relationship from child -> parent type exists, SwiftSync uses it
- if 0 or >1 candidates exist, SwiftSync throws and asks for explicit `parentRelationship`
- inferred parent sync defaults to `identityPolicy = .global` unless you pass `.scopedByParent` in the call

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
- nested to-one by relationship key (for example `company`)
- nested to-many by relationship key (for example `members`)

No wrapper extension is required when using `@Syncable`.
For custom merge policies, keep manual `applyRelationships(...)` implementations.

## 3) Ordered to-many support

SwiftSync currently does not provide ordered relationship sync semantics.

- SwiftData does not expose Core Data-style ordered relationship metadata for this pipeline.
- To-many sync is treated as unordered membership.
- If you need deterministic order in UI, store an explicit scalar order field and use `@SyncQuery(..., sortBy: ...)`.

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

## 6) Missing key vs `null` (field-level updates)

This is a hard contract for payload semantics:
- missing key => no-op (do not mutate existing local value)
- explicit `null` => clear value/relationship
- explicit `[]` on to-many => clear membership

If backend wants to remove/clear, it should send explicit `null` (or `[]` for to-many), not omit the key.
