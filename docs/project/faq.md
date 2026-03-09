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

Yes, if the model uses parent-scoped identity.

- `ParentScopedModel` defaults to `.scopedByParent`
- explicit parent-relationship sync on non-`ParentScopedModel` types defaults to `.global`
- `@Attribute(.unique)` on raw `id` still enforces global uniqueness at the store level

See `docs/project/parent-scope.md`.

## 3) Why does parent-scoped sync need `relationship`?

Because SwiftSync must know which child->parent relationship defines the sync scope (especially for scoped delete/diff).

- parent-scoped sync always passes an explicit `relationship:` key path

See `docs/project/parent-scope.md`.

## 4) How do I think about `@SyncQuery` filtering?

Use this mental rule:
- `relationship:` + `relationshipID:` = relationship-scoped query by ID
- `relationship:` always names the relationship path used by the query
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

## 9) How do key mapping defaults work (`snake_case`, camelCase, `@RemoteKey`)?

Convention-first.

- inbound key style is configured once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional)
- `@RemoteKey` overrides conventions
- import/export follow the same mapping contract

See `docs/project/property-mapping-contract.md`.

## 10) Are any model property names blocked?

Yes for `@Syncable` models: `description`, `hashValue`.

Use names like `descriptionText` / `hashValueRaw`, and map backend keys with `@RemoteKey` if needed.

See `docs/project/property-mapping-contract.md`.

## 11) Can I control relationship insert/update/delete work per sync call?

Yes. Use `relationshipOperations` (default: `.all`).

Use this when you want row updates but need to narrow relationship-side work for a specific sync pass.

## 12) What if payload has duplicate rows with the same identity?

Later payload rows win (payload order is applied in order).

## 13) What if local storage already has duplicate rows for the same identity?

SwiftSync deduplicates local identity collisions during sync and keeps one logical row per identity.

## 14) What if a row has missing or `null` primary key?

That row is skipped for matching/diffing. Sync continues for valid rows.

## 15) What happens when a scalar payload value is `null`?

- optional scalar -> `nil`
- non-optional primitive scalar -> default fallback (`""`, `0`, `false`, epoch date, zero UUID)

See `docs/project/property-mapping-contract.md`.

## 16) What happens if two sync calls run at the same time?

SwiftSync serializes sync calls per `ModelContainer`.

- same `ModelContainer` => queued, no overlap
- different stores => can run concurrently

This is enforced by an internal per-container sync lease, not by app code needing to add its own lock.

## 17) How do I cancel a sync?

Use Swift Concurrency task cancellation (`task.cancel()`).

SwiftSync cooperatively cancels and rolls back unsaved in-memory work for that run.

## 18) In app code, should views perform saves directly?

Recommended pattern: no.

- views collect intent and display local reactive state
- a domain/service layer performs backend mutations and syncs local storage
- views re-render from `@SyncQuery` / `@SyncModel`

See `docs/project/reactive-reads.md` ("App Best Practices").

## 19) Should I pass SwiftData model objects between views/sheets?

Recommended default: no.

- pass IDs/scalars
- child view owns/queries the data it needs
- avoid model-object handoff across navigation/sheet boundaries

This keeps view ownership explicit and avoids stale retained-reference assumptions.

See `docs/project/reactive-reads.md` ("App Best Practices").

## 20) What is the inverse rule for many-to-many relationships?

The corrected rule is narrower than what we first documented:

- this is a **many-to-many** issue (not a general all-to-many issue)
- one-to-many relationships work fine without explicit inverses
- many-to-many pairs should have **one explicit inverse anchor** (`@Relationship(inverse: ...)`) on either side
- do not force both sides if SwiftData throws the circular `@Relationship` macro compiler error

We removed the earlier broad `@Syncable` warning/allowlist because it encoded the wrong rule.

See `docs/project/relationship-integrity.md`.
