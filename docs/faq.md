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

Parent relationship inference is the default behavior when you call parent sync without `ParentScopedModel`:
- if exactly one to-one relationship from child -> parent type exists, SwiftSync uses it
- `parentRelationship` is only required when more than one candidate exists
- if zero candidates exist, SwiftSync throws because parent-scoped sync cannot be resolved for that model
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
Scalar attributes still support deterministic coercion paths where appropriate:
- parseable string -> numeric (`Int`, `Double`, `Float`, `Decimal`)
- numeric -> numeric (`Int`, `Double`, `Float`, `Decimal`)
- string/0/1 numeric -> `Bool`
- string -> `UUID`, `URL`
- common primitives -> `String`

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

## 7) Deep-path mapping (`@RemotePath`)

`@RemotePath` is supported for both import and export.

- Example: `@RemotePath("profile.contact.email") var email: String?`
- Inbound sync resolves dotted keys from nested dictionaries.
- Outbound export writes nested dictionaries for dotted paths.
- Missing vs `null` semantics are unchanged for deep paths.

## 8) Input key style (`snake_case` vs `camelCase`)

Configure inbound key style once at `SyncContainer`:
- `.snakeCase` (default)
- `.camelCase`

The configured style is applied across attributes and relationship mapping, including deep paths.

## 9) Blocked model property names

For `@Syncable` models, SwiftSync emits compile-time diagnostics for blocked names:
- `description`
- `hashValue`

Recommended replacements:
- `descriptionText`
- `hashValueRaw`

Use `@RemoteKey` if backend keys still use the blocked names.

## 10) `@SyncQuery` with `parent`

`@SyncQuery` supports parent-scoped reads:

```swift
@SyncQuery(
  Comment.self,
  parent: task,
  in: syncContainer,
  sortBy: [SortDescriptor(\Comment.id)]
)
var comments: [Comment]
```

Inference rule is the same as parent sync:
- exactly one to-one relationship to the parent type => inferred automatically
- ambiguous (more than one) => pass `parentRelationship:` explicitly
- none => fail fast with a clear diagnostic

Use `predicate` instead when:
- filtering by many-to-many membership
- filtering by scalar FK values without a parent object instance
- applying non-parent business filters
