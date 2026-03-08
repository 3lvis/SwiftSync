# State Capsule

## Plan
- [x] Add failing tests that codify container-owned export configuration (`keyStyle` and `dateFormatter`) and container export entry points.
- [x] Implement `SyncContainer.export(...)` APIs (unscoped and parent-scoped) that always derive options from container configuration.
- [x] Remove public `SwiftSync.export(...)` entry points from the external API surface and route call sites/tests to container exports.
- [x] Update README/API docs to container-owned export configuration and remove per-call export key-style guidance.
- [x] Run targeted and full `swift test` to verify behavior.

## Last known state
`swift test --filter ExportTests` and full `swift test` are green.

## Decisions (don't revisit)
- Standardize export configuration on `SyncContainer`; no backward compatibility for per-call export options in public API.

## Files touched
- .agents/state.md
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Sources/SwiftSync/API.swift
- README.md
- docs/planning/demo-coverage-gap.md
