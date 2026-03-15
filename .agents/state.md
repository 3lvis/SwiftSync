# State Capsule

## Plan

- [x] Inspect the export APIs, tests, and call sites to choose a safe cleanup order
- [x] Implement the export API cleanup in `SwiftSync/**` by removing bulk export and deleting bulk-only tests/benchmarks
- [~] Update docs and planning notes to match the remaining export surface
- [x] Run relevant SwiftSync tests and review the final diff

## Last known state

bulk export removed from `SyncContainer`; export tests pass with single-object coverage; remaining follow-up is object-export naming/docs

## Decisions (don't revisit)

- Work on a feature branch because implementation on `master` is disallowed
- Follow library TDD for changes in `SwiftSync/**`
- Decide cleanup order from current code and test usage rather than renaming surfaces blindly
- Remove the bulk export API entirely rather than preserving an internal helper

## Files touched

- .agents/state.md
- docs/planning/export-api-cleanup.md
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
