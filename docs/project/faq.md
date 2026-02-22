# SwiftSync FAQ

This is the single FAQ for SwiftSync.

Related docs:
- backend payload contract: `docs/project/backend-contract.md`
- parent-scoped sync/query behavior: `docs/project/parent-scope.md`

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

## 10) `@SyncQuery` with `toOne` / `toMany`

`@SyncQuery` supports relationship-scoped reads.

To-one (`belongs to`):

```swift
@SyncQuery(
  Comment.self,
  toOne: task,
  in: syncContainer,
  sortBy: [SortDescriptor(\Comment.id)]
)
var comments: [Comment]
```

To-many (`contains` / membership):

```swift
@SyncQuery(
  Tag.self,
  toMany: task,
  in: syncContainer,
  sortBy: [SortDescriptor(\Tag.id)]
)
var tags: [Tag]
```

Inference rule is the same idea as parent sync:
- exactly one to-one relationship to the parent type => inferred automatically
- exactly one to-many relationship to the related type => inferred automatically
- ambiguous (more than one) => pass `via:` explicitly
- none => fail fast with a clear diagnostic

Use `predicate` instead when:
- filtering by scalar FK values without a parent object instance
- applying non-parent business filters

## 11) Do I have to import multiple modules?

No. Use only:

```swift
import SwiftSync
```

## 12) What if payload has duplicate items with the same identity?

SwiftSync applies payload rows in order. If the same identity appears more than once, later rows win.

## 13) What if local DB already has duplicate rows for the same primary key?

SwiftSync deduplicates local identity collisions during sync and keeps one logical row per identity.

## 14) What if a row has missing or `null` primary key?

That row is skipped for matching/diffing. Sync continues for valid rows.

## 15) What happens when payload value is `null` for a scalar?

- optional scalar -> `nil`
- non-optional primitive scalar -> default value (`""`, `0`, `false`, epoch date, zero UUID)

## 16) What happens if two sync calls run at the same time?

SwiftSync serializes sync calls per store/container.

- Calls targeting the same `ModelContainer` are queued (no overlap/interleaving).
- Final state is last-writer-wins by queued execution order.
- Calls targeting different stores can run concurrently.

More internal test-planning detail lives in `docs/planning/swiftdata-concurrency-edge-cases.md`.

## 17) How do I cancel a sync?

Use Swift Concurrency task cancellation:

```swift
let task = Task {
  try await SwiftSync.sync(payload: payload, as: User.self, in: context)
}

task.cancel()

do {
  try await task.value
} catch SyncError.cancelled {
  // expected cooperative cancellation
}
```

Cancellation is cooperative. SwiftSync rolls back unsaved in-memory changes for that run, but it does not roll back work that was already saved earlier.

## 18) Can I still control sort direction with `@SyncQuery`?

Yes. Use explicit `SortDescriptor` values when you need direction:

```swift
@SyncQuery(
  Task.self,
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.priority, order: .reverse),
    SortDescriptor(\Task.id)
  ]
)
var tasks: [Task]
```

## 19) When should I use `sortBy: [\.field]` vs `sortBy: [SortDescriptor(...)]`?

- Use `sortBy: [\.field]` for concise default ascending sort.
- Use `sortBy: [SortDescriptor(...)]` for descending or mixed ordering.
- If your model is not `@Syncable`, shorthand requires `SyncQuerySortableModel` conformance; explicit `SortDescriptor` works directly.
