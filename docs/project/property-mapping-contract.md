# Property Mapping Contract

Read this when you need to know exactly how SwiftSync interprets payload keys, `null`, relationships, and export keys.

If you only need the practical rule set, start here:
- convention-first mapping is the default
- missing key means ignore
- explicit `null` means clear
- `@RemoteKey` and `@PrimaryKey(remote:)` override conventions

This document is the source of truth for the detailed behavior behind those rules.

## Scope

This contract defines current behavior for:
- inbound key resolution
- null/missing semantics
- relationship key conventions
- container-level input key style
- export key emission contract
- scalar type coercion policy

## Core Rules

- Convention-first mapping is expected.
- `absent = ignore` for payload fields.
- `null = clear` for optional fields/relationships when delete semantics apply.
- Explicit overrides (`@PrimaryKey(remote:)`, `@RemoteKey`) take precedence over conventions.

Practical defaults:
- Prefer convention mapping first; add `@RemoteKey` only when local naming intentionally differs.
- Prefer `projectID`, `remoteURL`, `uuidValue` style names; SwiftSync normalizes acronyms for snake/camel mapping.
- Configure inbound key style once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional).

## Container Input Key Style

Inbound key style is configured at `SyncContainer`:
- `.snakeCase` (default)
- `.camelCase`

The configured style is applied to all payload lookups performed during sync.

## Inbound Key Resolution (Attributes)

For generated model input keys:
1. `@PrimaryKey(remote:)` if present
2. `@RemoteKey` if present
3. property name by convention

Lookup behavior in `SyncPayload`:
1. style-transformed candidate (based on container `keyStyle`)
2. literal requested key
3. identity aliases (`id`/`remote_id`/`remoteID` as applicable)

Example:
- Property `projectID`
- `.snakeCase` mode accepts `project_id`
- `.camelCase` mode accepts `projectId`

## Inbound Key Resolution (Relationships)

Relationship lookup uses the same `SyncPayload` candidate pipeline.

Foreign-key conventions:
- to-one: `<relationship>_id`
- to-many IDs: `<relationship>_ids` and singularized fallback (`watcher_ids` for `watchers`)
- `@RemoteKey` overrides FK convention

Nested-object conventions:
- relationship name by convention
- `@RemoteKey` may target nested key paths using dotted notation

Dispatch order for relationships:
1. if FK key is present, process FK path
2. else if nested key is present, process nested object path

Deep-path behavior:
- dotted keys (for example `relationships.owner`) are resolved against nested dictionaries on import.
- deep-path lookup uses the same key-style candidate pipeline (`snakeCase`/`camelCase`) as flat keys.
- nested relationship payload processing keeps the parent sync key-style configuration.

## Null and Missing Semantics

- Missing key: no change.
- Explicit `NSNull`:
- optional scalar: clears to `nil`
- non-optional scalar: resets to default fallback in required reads
- optional relationship: clears when delete operation is enabled
- non-optional relationship: cannot be cleared

Relationship operation flags still gate insert/update/delete behavior.

## FK Typing and Unknown References

- FK parsing is strict for relationship IDs.
- Unknown FK references are soft no-ops (no placeholder creation, no forced clear).

## Reserved Name Diagnostics

For `@Syncable` models, SwiftSync emits compile-time diagnostics for blocked names:
- `description` (suggested replacement: `descriptionText`)
- `hashValue` (suggested replacement: `hashValueRaw`)

When payload keys still use blocked names, map them with `@RemoteKey`.

## Export Key Contract

Export key precedence:
1. `@RemoteKey`
2. `@PrimaryKey(remote:)`
3. convention transform from export `keyStyle`

Defaults:
- export key style defaults to snake_case
- relationship export mode defaults to array mode

Round-trip expectation:
- if import/export use matching conventions and no divergent overrides, exported keys match expected API keys.

## Scalar Coercion Matrix

Supported scalar coercions on inbound attribute reads include:
- string -> numeric (`Int`, `Double`, `Float`, `Decimal`) when parseable
- integer/number -> `Double`, `Float`, `Decimal`
- number -> `Int` (truncating numeric conversion)
- string -> `Bool` (`true/false`, `1/0`, `yes/no`)
- numeric `0/1` -> `Bool`
- string -> `UUID`
- string -> `URL`
- `UUID`/`URL`/numeric/bool/decimal -> `String`
- string/number -> `Date` via parser and unix timestamp handling

Strict reads (`strictValue`, relationship FK linking) remain non-coercive by design.

## Uniqueness Constraints (identity only)

Declare uniqueness **only on the sync identity** (the `id` / `@PrimaryKey` property). Do **not**
put `@Attribute(.unique)` or `#Unique` (single or compound) on any other property of a synced model.

SwiftSync identifies rows by `syncIdentity` and upserts by fetching the existing row, then
updating or inserting — one row per identity is the core invariant. SwiftData enforces unique
constraints with its own *constraint-based* upsert: inserting a row that collides on a unique
property silently overwrites the existing row. When those two disagree — e.g. two
identity-distinct records that happen to share a `email` you marked unique — sync **silently
destroys** one of them, and the local store ends up with fewer rows than the backend sent, with
no error.

Guardrail: `SyncContainer` validates this at init and throws `SchemaValidationError` if a
`@Syncable` model declares a uniqueness constraint on a non-identity property (alongside the
existing many-to-many inverse check). `#Index` on any property is unaffected — it only changes
query planning and is safe to use freely. Hand-written `SyncUpdatableModel` conformances are not
checked (they leave `syncIdentityPropertyName` empty); the same rule applies to them by
convention.

## SwiftData query features (`#Index`, `#Expression`)

Both are **transparent to SwiftSync** — use them freely. For consumer-model queries SwiftSync builds
only identity- and parent-scope predicates internally (its own history-author and token-record
predicates are a separate, internal concern), and never inspects or restricts how a consumer
constructs a query:

- `#Index` affects only query planning, never sync semantics. (The uniqueness guardrail above
  rejects a non-identity *unique* constraint, but leaves indexes untouched.)
- `#Expression` composes into a consumer's `#Predicate`. `@SyncQuery` / `SyncQueryPublisher` accept
  any `Predicate<Model>` and pass it straight to `FetchDescriptor`, so an `#Expression`-built
  predicate works unchanged. SwiftSync neither requires nor exposes `#Expression` in its own API —
  it is out of scope for the library surface and fully available to consumers.
