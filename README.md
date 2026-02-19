# SwiftSync

A minimal SwiftData sync framework.

## Status

- Proposed
- Audience: iOS engineers
- Current scope: inbound sync only (`server -> local`)
- Deferred: outbound export (`local -> server`)

## Goal

Ship a reliable `sync` API first.

## Non-Goals (for now)

- No networking layer.
- No outbound queue/reconciliation.
- No agent-specific APIs.
- No broad compatibility/migration framework.
- No performance hardening work until core behavior is stable.

## Minimal Public API

```swift
public enum SwiftSync {}

public extension SwiftSync {
  static func sync<Model: SyncUpdatableModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext
  ) async throws

  static func sync<Model: ParentScopedModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    parent: Model.SyncParent
  ) async throws
}
```

## Model Contract (Milestone 1)

Models participating in sync conform to `SyncUpdatableModel`:

- declare identity key path
- provide `make(from:)` for inserts
- provide `apply(_:)` for updates with field-by-field comparison (return `true` only if a value changed)

`SyncPayload` provides snake_case/camelCase lookup and `id`/`remoteID` identity key conventions.
Top-level payload rows without a valid identity are skipped during matching/diffing.
Custom primary keys can be declared with `@PrimaryKey` on a model property (no string key configuration required).
Numeric payload values are coerced leniently for `Int` identity fields (for example, `42.9` becomes `42`).
ISO8601 date strings are coerced to `Date` values (for example, `updated_at` -> `updatedAt`).
Explicit `null` clears optional scalars to `nil`; for non-optional primitive scalars it applies type defaults (for example `""`, `0`, `false`, epoch date, zero UUID).
our policy is honestly we do our best without affecting performance.

For relationship updates, models can additionally conform to `SyncRelationshipUpdatableModel` and apply to-one/to-many changes during the same sync run.

For child-only payload sync scoped to one parent, models can conform to `ParentScopedModel` and use the `parent:` overload.
Behavior:

- created/updated children are linked to the provided parent relationship
- diff/delete scope is limited to rows already linked to that parent
- children linked to other parents are unaffected

To-one relationships can be handled either as nested objects (for example, `"owner": {...}`) or by foreign-key scalar fields (for example, `"company_id": 10`) inside `applyRelationships`.
For `*_id` fields, recommended behavior is:

- non-null id: fetch referenced model by primary key and link if found
- explicit `null`: clear the relationship
- missing key: preserve existing relationship
- missing referenced row: no crash; leave relationship unset unless your app explicitly supports stubs

For to-many nested object arrays (for example, `"messages": [{...}, {...}]`), recommended behavior is payload-membership source-of-truth for that parent:

- payload A sets relation membership to A ids
- payload B replaces relation membership with B ids
- overlapping child ids are updated in place (upsert)
- ids removed from B are no longer related to the parent

For to-many foreign-key scalar arrays (for example, `"notes_ids": [1, 2]`) inside `applyRelationships`:

- relation should match exactly the resolved id list for that parent
- links not present in the latest `*_ids` payload are removed
- repeating the same payload is idempotent
- missing referenced ids should not crash; unresolved ids can be ignored unless your app explicitly supports stubs

For many-to-many relationships, nested-object and `*_ids` forms should converge to the same final join graph when they represent the same intended links.

### Date Parsing Contract

`Core` includes `SyncDateParser` for inbound mapping hot paths:

- `SyncDateParser.dateFromDateString(_:)`
- `SyncDateParser.dateFromISO8601String(_:)`
- `SyncDateParser.dateFromUnixTimestampString(_:)`
- `SyncDateParser.dateFromUnixTimestampNumber(_:)`
- `String.dateType()` (`iso8601` vs `unixTimestamp`)

Behavior:

- Date-only `YYYY-MM-DD` is normalized to UTC midnight.
- `YYYY-MM-DD HH:MM:SS` is accepted by converting the space to `T`.
- Timezone forms supported: `Z`, `+00:00`, `+0000`, and no timezone (defaults to UTC).
- Fractional seconds support includes deciseconds, centiseconds, milliseconds, and microseconds.
- Microseconds are truncated to millisecond precision.
- Invalid date text returns `nil`; sync mapping never crashes on invalid date values.
- Unix timestamps support seconds and long microseconds-like forms (string and numeric input).

## Principles

1. Keep API small.
2. Prefer convention over custom DSL when possible.
3. Add features only when a concrete use case requires them.
4. Make behavior deterministic.
5. Fail clearly with typed errors.

## Internal Direction (not public API)

- Parse payload
- Decide changes
- Apply changes in `ModelContext`

This can evolve internally without growing public surface area.

## Example

```swift
try await SwiftSync.sync(
  payload: usersPayload,
  as: User.self,
  in: modelContext
)
```

## Custom Primary Key Example

```swift
@Syncable
@Model
final class ExternalUser {
  @PrimaryKey
  @Attribute(.unique) var xid: String
  var name: String
}
```

Without `@PrimaryKey`, `@Syncable` falls back to `id`/`remoteID` conventions.

If the remote key differs from the local property name:

```swift
@Syncable
@Model
final class ExternalMappedUser {
  @PrimaryKey(remote: "external_id")
  @Attribute(.unique) var xid: String
  var name: String
}
```

## Milestones

### Milestone 0: Foundation

- Buildable package
- Demo app scaffold
- Basic sync wiring
- Basic tests and CI

### Milestone 1: Inbound Happy Path

- snake_case -> camelCase mapping
- identity mapping (`id`, `remoteID`)
- source-of-truth diff behavior (insert/update/delete)
- write-on-change behavior via field-by-field comparison for matching identities

### Milestone 2: Relationships

- common to-one and to-many behavior
- `SyncRelationshipUpdatableModel` hook for relationship diff application

### Milestone 3: Hardening Sync

### Milestone 4: Export
