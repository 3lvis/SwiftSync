# SwiftSync FAQ

This is the single FAQ for SwiftSync.

Source-of-truth docs:
- `docs/project/parent-scope.md` (parent-scoped sync/query behavior)
- `docs/project/property-mapping-contract.md` (mapping/import/export semantics)
- `docs/project/reactive-reads.md` (`@SyncQuery` / `@SyncModel` mental model)
- `docs/project/relationship-integrity.md` (many-to-many inverse anchor rule)
- `docs/project/backend-contract.md` (recommended backend shape)

If an answer needs more than a short explanation, this FAQ points to the source-of-truth doc instead of duplicating it.

## 1) Do I need to import multiple modules?

No. Use only:

```swift
import SwiftSync
```

## 2) Can two different parents have children with the same `id`?

Yes, if the model uses `ParentScopedModel`. Note that `@Attribute(.unique)` on raw `id` still enforces global uniqueness at the store level.

See `docs/project/parent-scope.md`.

## 3) Why does parent-scoped sync need relationship inference / `parentRelationship`?

Because SwiftSync must know which child->parent relationship defines the sync scope (especially for scoped delete/diff).

- exactly one candidate => inferred
- ambiguous => explicit `parentRelationship`
- none => fail fast

See `docs/project/parent-scope.md`.

## 4) How do I think about `@SyncQuery` filtering?

Use this mental rule:
- `relatedTo:` + `relatedID:` = relationship-scoped query by ID
- `through:` = explicit relationship path for ambiguous cases
- Demo example: `Task -> User` is ambiguous once `Task` has `assignee`, `reviewer`, and `watchers`, so `through:` is required there
- `predicate:` = custom business filters or scalar-only filters

See `docs/project/reactive-reads.md`.

## 5) What does `refreshOn:` mean in `@SyncQuery`?

It expands what related model changes should invalidate/refetch the query.

Use it when the UI reads related data that is not part of the query model's own scalar fields.

See `docs/project/reactive-reads.md`.

## 6) Is missing field the same as `null`?

No.

- missing key => no-op (`absent = ignore`)
- explicit `null` => clear
- explicit `[]` for to-many => clear membership

See `docs/project/property-mapping-contract.md` and `docs/project/backend-contract.md`.

## 7) How strict is relationship FK (`*_id`) linking?

Strict by type.

- `Int` FK links to `Int` identity
- `String` FK links to `String` identity
- no cross-type coercion at relationship-link step

Scalar attribute coercion is broader; relationship FK linking is intentionally stricter.

See `docs/project/property-mapping-contract.md`.

## 8) Does SwiftSync support ordered to-many relationship syncing?

Not as ordered relationship semantics.

Treat to-many sync as unordered membership and store an explicit scalar order field if UI order matters.

See `docs/project/property-mapping-contract.md` and `docs/project/backend-contract.md`.

## 9) How do key mapping defaults work (`snake_case`, camelCase, `@RemotePath`)?

Convention-first.

- inbound key style is configured once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional)
- `@RemoteKey` / `@RemotePath` override conventions
- import/export follow the same mapping contract

See `docs/project/property-mapping-contract.md`.

## 10) Are any model property names blocked?

Yes for `@Syncable` models: `description`, `hashValue`.

Use names like `descriptionText` / `hashValueRaw`, and map backend keys with `@RemoteKey` if needed.

See `docs/project/property-mapping-contract.md`.

## 11) Can I control relationship insert/update/delete work per sync call?

Yes. Use `relationshipOperations` (default: `.all`).

Use this when you want row updates but need to narrow relationship-side work for a specific sync pass.

## 12) What does `missingRowPolicy` do?

It controls what happens to local rows missing from the payload in that sync scope:

- `.delete` (default)
- `.keep`

For parent-scoped sync, delete behavior is scoped to that parent subset.

## 13) What if payload has duplicate rows with the same identity?

Later payload rows win (payload order is applied in order).

## 14) What if local storage already has duplicate rows for the same identity?

SwiftSync deduplicates local identity collisions during sync and keeps one logical row per identity.

## 15) What if a row has missing or `null` primary key?

That row is skipped for matching/diffing. Sync continues for valid rows.

## 16) What happens when a scalar payload value is `null`?

- optional scalar -> `nil`
- non-optional primitive scalar -> default fallback (`""`, `0`, `false`, epoch date, zero UUID)

See `docs/project/property-mapping-contract.md`.

## 17) What happens if two sync calls run at the same time?

SwiftSync serializes sync calls per store/container.

- same `ModelContainer` => queued, no overlap
- different stores => can run concurrently

More implementation/test-planning detail lives in `docs/planning/swiftdata-concurrency-edge-cases.md`.

## 18) How do I cancel a sync?

Use Swift Concurrency task cancellation (`task.cancel()`).

SwiftSync cooperatively cancels and rolls back unsaved in-memory work for that run.

## 19) `@SyncQuery` sorting: shorthand vs explicit `SortDescriptor`

- `sortBy: [\.field]` => concise ascending sort
- `sortBy: [SortDescriptor(...)]` => descending/mixed ordering
- shorthand requires `SyncQuerySortableModel` (or `@Syncable` generated support)

## 20) In app code, should views perform saves directly?

Recommended pattern: no.

- views collect intent and display local reactive state
- a domain/service layer performs backend mutations and syncs local storage
- views re-render from `@SyncQuery` / `@SyncModel`

See `docs/project/reactive-reads.md` ("App Best Practices").

## 21) Should I pass SwiftData model objects between views/sheets?

Recommended default: no.

- pass IDs/scalars
- child view owns/queries the data it needs
- avoid model-object handoff across navigation/sheet boundaries

This keeps view ownership explicit and avoids stale retained-reference assumptions.

See `docs/project/reactive-reads.md` ("App Best Practices").

## 22) What is the inverse rule for many-to-many relationships?

The corrected rule is narrower than what we first documented:

- this is a **many-to-many** issue (not a general all-to-many issue)
- one-to-many relationships work fine without explicit inverses
- many-to-many pairs should have **one explicit inverse anchor** (`@Relationship(inverse: ...)`) on either side
- do not force both sides if SwiftData throws the circular `@Relationship` macro compiler error

We removed the earlier broad `@Syncable` warning/allowlist because it encoded the wrong rule.

See `docs/project/relationship-integrity.md`.
