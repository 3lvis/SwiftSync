# Backend Contract For Minimal SwiftSync Boilerplate

This is the recommended API contract when backend and iOS are co-designed for SwiftSync.

The goal is simple:
- near-zero model mapping boilerplate
- predictable partial-update semantics
- deterministic sync behavior

## 1) Identity Rules

Use one stable identity key per resource:
- default: `id`
- keep identity type stable per resource (`Int` stays `Int`, `String` stays `String`)

For parent-scoped resources:
- decide explicitly: global identity vs parent-scoped identity
- if parent-scoped, treat identity as `(parent_id, id)` at API-contract level

## 2) Naming Rules

Use snake_case API keys that map cleanly to Swift camelCase:
- scalar: `display_name` -> `displayName`
- to-one FK: `<relation>_id` (example: `assignee_id`)
- to-many FK: `<relation>_ids` (example: `tag_ids`)
- nested objects/arrays: relation key itself (example: `assignee`, `members`)

This minimizes `@RemoteKey` usage.

## 3) Null/Missing Semantics (Required)

Treat these as different states:
- key missing => no-op
- key present with `null` => clear
- key present with `[]` on to-many => clear membership

Strong rule:
- clear/remove/delete intent must be explicit (`null` / `[]`), never inferred from omission

Implementation guidance:
- serializers must not silently drop explicit nulls
- write contract tests for null/missing behavior per endpoint

## 4) Relationship Shape Policy

Default to FK payloads for sync endpoints:
- to-one: `*_id`
- to-many: `*_ids`

Use nested relationship objects only when you intentionally want child upsert behavior in the same payload.

Do not mix relationship shapes unpredictably within the same endpoint contract.

## 5) Parent Scope Rules

For parent-scoped endpoints:
- include `parent_id` explicitly, or guarantee scope by endpoint path and keep it stable
- apply delete/missing-row semantics only within that parent scope

## 6) Ordering Policy (Current SwiftData Reality)

Do not rely on ordered relationship semantics.

Use explicit scalar order fields when order matters:
- `position` or `sort_index`
- query via `sortBy` in SwiftSync read layer

## 7) Sync Metadata

Include `updated_at` on all syncable resources.

Recommended next step for incremental sync:
- add monotonic `version`/`revision` per row (or equivalent server sequence)

Optional for soft-delete flows:
- add `deleted_at` tombstones with explicit retention policy

## 8) Compatibility / Rollout Guidance

For existing APIs:
- preserve backward compatibility with versioned endpoints
- migrate resource-by-resource to this contract
- add fixture-based contract tests to avoid drift

---

## Implemented In This Repo

Current demo backend payloads now follow:
- stable `id`
- snake_case naming
- `*_id` / `*_ids` relationship keys
- explicit `null` emission for optional fields in task payloads
- `updated_at` on all demo resources
- no ordered-relationship assumptions
