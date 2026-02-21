# Property Mapping Contract v2

This document is the source of truth for property mapping behavior in SwiftSync.

## Scope

This contract defines current behavior for:
- inbound key resolution
- null/missing semantics
- relationship key conventions
- container-level input key style
- export key emission contract
- scalar type coercion policy

It also marks deferred items that are planned but not part of this phase.

## Core Rules

- Convention-first mapping is expected.
- `absent = ignore` for payload fields.
- `null = clear` for optional fields/relationships when delete semantics apply.
- Explicit overrides (`@PrimaryKey(remote:)`, `@RemoteKey`, `@RemotePath`) take precedence over conventions.

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
1. style-transformed candidate (based on `inputKeyStyle`)
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
- to-many IDs: `<relationship>_ids` and singularized fallback (`tag_ids` for `tags`)
- `@RemoteKey` overrides FK convention

Nested-object conventions:
- relationship name by convention
- `@RemotePath` adds explicit nested key path for that relationship key

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
1. `@RemotePath`
2. `@RemoteKey`
3. `@PrimaryKey(remote:)`
4. convention transform from `ExportOptions.keyStyle`

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

## Deferred (Later Phases)

- Deep-path import test expansion for additional to-many nested relationship variants.
- Additional coercion matrix hardening beyond the current deterministic set.
- Reserved-name diagnostics expansion if new SwiftData/Swift collisions are identified.
