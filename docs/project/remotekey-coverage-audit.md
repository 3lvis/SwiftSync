# RemoteKey Coverage Audit

## Scope

This document records current coverage for `@RemoteKey` after removal of `@RemotePath`.

Goal: verify whether `@RemoteKey` covers realistic mapping scenarios for both import (sync) and export.

## Bottom line

`@RemoteKey` currently covers all realistic scenarios used by this codebase contract:

- flat scalar key remapping
- nested scalar key/path remapping (dotted path)
- relationship foreign-key remapping
- relationship nested-object remapping (including dotted nested paths)
- export of nested dotted paths

No high-priority functional gaps were found in the current contract surface.

## Covered scenarios (with test evidence)

Import (sync):

- custom primary key remote mapping via `@PrimaryKey(remote:)`
  - `SwiftSync/Tests/SwiftSyncTests/SyncTests.swift`
  - `testSyncUsesCustomPrimaryKeyWithRemoteKeyMapping`
- nested scalar mapping via dotted `@RemoteKey`
  - `SwiftSync/Tests/SwiftSyncTests/SyncTests.swift`
  - `testSyncNestedRemoteKeyScalarImportsDeepValueWithMissingAndNullSemantics`
  - `testSyncNestedRemoteKeyScalarRespectsContainerCamelCaseMode`
  - `testSyncNestedRemoteKeyScalarWithDirectContext`
- nested relationship mapping via dotted `@RemoteKey`
  - `SwiftSync/Tests/SwiftSyncTests/SyncTests.swift`
  - `testSyncNestedRemoteKeyToOneRelationshipImportsAndClears`
- relationship FK behavior and to-many ID semantics
  - `SwiftSync/Tests/SwiftSyncTests/SyncTests.swift`
  - `testSyncableGeneratedToManyIDsDedupeUnknownMissingAndNull`
  - `testSyncContainerCamelCaseInputKeyStyleMapsCamelToManyForeignKeys`

Export:

- custom primary key remote mapping on export
  - `SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift`
  - `testExportPrimaryKeyRemoteMapping`
- nested scalar key/path export via dotted `@RemoteKey`
  - `SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift`
  - `testExportNotExportAndNestedRemoteKey`
  - `testExportNilNestedRemoteKeyAlwaysEmitsNSNull`
- update-body mapping with nested dotted keys via `exportObject`
  - `SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift`
  - `testBuildUpdateBodyUsesRemoteKeyMappings`

## Remaining coverage gaps

No required additional scenarios are currently identified for the existing public contract.

If new backend contracts appear, add tests only when they introduce new behavior (not syntax-only variants).

## Gotchas

- Relationship dispatch is shape-sensitive:
  - if the payload value at a relationship key is a scalar ID (or ID array), the FK path is used
  - if the payload value is an object (or object array), the nested-object path is used
- Dotted `@RemoteKey("a.b.c")` relies on nested dictionary payload shape, not a flat literal key.
- Missing key means no mutation; explicit `null` means clear/delete when allowed by relationship operations.
- Key-style mode (`snakeCase`/`camelCase`) still applies to candidate key resolution for path segments.
- For to-many relationships, membership is treated as unordered by design.
