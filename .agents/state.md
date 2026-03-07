# State Capsule

## Plan
- [x] Confirm branch state and carry current planning-doc edits onto the feature branch.
- [x] Add export hardening tests for unsupported scalar fallback, Data/Decimal encoding, and bare `@PrimaryKey` mapping.
- [x] Run targeted `swift test --filter ExportTests` and fix any failures.
- [x] Update planning notes/results and verify branch status.

## Last known state
`swift test --filter ExportTests` passed (21 tests, 0 failures) after adding hardening coverage in `SyncExportTests`; branch has intended uncommitted changes only.

## Decisions (don't revisit)
- Keep this task scoped to export hardening tests and related planning docs only.
- No source-level API doc changes for this pass.

## Files touched
- .agents/state.md
- docs/planning/export-improvements.md
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
