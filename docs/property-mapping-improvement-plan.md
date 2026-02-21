# Property Mapping Improvement Plan

This is the implementation plan for improving SwiftSync property mapping using the legacy Core Data notes as input, while keeping SwiftData-first design.

## Goal

Make mapping behavior predictable, convention-first, and low-boilerplate:
- fewer required `@RemoteKey` annotations
- consistent snake_case/camelCase handling
- safer handling for reserved property names in SwiftData models
- explicit, testable behavior for null/missing/deep paths
- container-level control over inbound key style
- export that round-trips back to expected API keys

## Current Findings We Must Address

1. Reserved names in SwiftData models:
- `description` is not allowed in `@Model`.
- `hashValue` is problematic/ambiguous in `@Model`.

2. Inflection gap:
- Current snake conversion is naive for acronyms (`projectID` can become `project_i_d`), causing unnecessary `@RemoteKey` usage.

3. Mapping consistency gaps:
- Attribute, FK, nested relationship, and deep-path behavior should share one coherent key-resolution policy.

4. Input style configuration:
- Inbound key style should be configured once at `SyncContainer` level.
- Supported modes should be only:
- `.snakeCase` (default)
- `.camelCase`

## Scope and Principles

What we keep from legacy:
- convention-first mapping
- missing key = no-op, explicit `null` = clear
- FK conventions (`*_id`, `*_ids`)
- strict relationship FK typing

What we do not copy blindly:
- Objective-C/Core Data internals
- legacy reserved-word list that does not apply to SwiftData

Core principle:
- "absent = ignore" applies to payload fields, not to unresolved model mapping.
- If model mapping cannot be resolved safely, fail fast with actionable diagnostics.

## Step-by-Step Plan (Broad Phases)

## Step 1: Define Mapping Contract v2

Deliver a single written contract for inbound/outbound mapping precedence:
- precedence order for keys (`RemotePath`, `RemoteKey`, convention candidates)
- null/missing semantics
- deep-path behavior
- relationship key policy (`*_id`, `*_ids`, nested object keys)
- failure policy for unresolved/ambiguous mapping
- `SyncContainer` inbound key style config (`snakeCase` default, `camelCase` optional)
- export key contract (which outbound keys are emitted by default and when overrides apply)

Exit criteria:
- approved spec document used as source of truth for implementation and tests.

## Step 2: Build Inflection Engine v2

Replace naive inflection with acronym-aware normalization:
- `projectID` -> `project_id`
- `remoteURL` -> `remote_url`
- `uuidValue` -> `uuid_value`

Apply inflection based on `SyncContainer` input style mode:
- `.snakeCase` mode resolves normalized snake keys
- `.camelCase` mode resolves camel keys

Exit criteria:
- core inflection utility introduced and used by mapping paths.

## Step 3: Unify Key Resolution Across Attributes and Relationships

Implement one shared key-resolution pipeline used by:
- scalar attributes
- to-one FK mapping
- to-many FK mapping
- nested relationship object mapping

Preserve strict FK typing for relationships.
Ensure this pipeline reads `SyncContainer` input style once and applies consistently.

Exit criteria:
- no divergent key-resolution rules between scalar and relationship paths unless explicitly documented.

## Step 4: Reserved Name Strategy (SwiftData-Specific)

Introduce a clear policy for blocked/sensitive model property names:
- enforce known blocked names (`description`, `hashValue`) with compile-time diagnostics where possible
- document canonical alternatives (`descriptionText`, etc.)
- keep remote payload mapping seamless via `@RemoteKey`/convention

Exit criteria:
- reserved-name behavior is documented, validated, and discoverable in error messages.

## Step 5: Deep Mapping and Export Symmetry

Align `@RemotePath` behavior for import/export:
- nested attribute paths
- nested relationship paths
- explicit null handling through deep paths
- outbound keys must match expected API keys (`RemotePath`/`RemoteKey` overrides first, convention fallback second)
- export behavior must support deterministic round-trip with the chosen API contract

Exit criteria:
- deep-path import and export behavior is symmetric and covered by tests.

## Step 6: Type Conversion Policy Hardening

Codify and test a coercion matrix:
- scalar coercions that are supported
- relationship FK conversions that remain strict
- date parsing behavior and fallback policy

Add only conversions that are deterministic and safe.

Exit criteria:
- conversion matrix is documented and backed by tests.

## Step 7: Test Matrix Expansion (Legacy-Parity-Informed)

Add focused tests for:
- acronym normalization candidates
- reserved-name diagnostics
- missing vs null semantics
- equal-value no-rewrite behavior
- unknown FK no-placeholder behavior
- relationship operation flags
- deep-path mapping cases
- container-level style mode behavior (`snakeCase` default, `camelCase` mode)

Exit criteria:
- regression suite covers all contract-critical mapping paths.

## Step 8: Demo + Documentation + Migration Rollout

Update demo models/payloads/docs to reflect new defaults:
- remove no-longer-needed `@RemoteKey` where conventions now cover mapping
- keep explicit keys where domain naming intentionally diverges
- publish migration notes with before/after examples

Exit criteria:
- demo compiles/tests pass, docs match runtime behavior, migration guidance is published.

## Implementation Order Recommendation

Run steps in this order:
1. Step 1
2. Step 2
3. Step 3
4. Step 7 (initial subset)
5. Step 4
6. Step 5
7. Step 6
8. Step 8

This order gives early value (fewer `@RemoteKey`s) while keeping behavior safe and test-first.
