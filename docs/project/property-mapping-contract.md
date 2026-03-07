# Property Mapping Contract

This document is the source of truth for property mapping behavior in SwiftSync.

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
3. convention transform from `ExportOptions.keyStyle`

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
