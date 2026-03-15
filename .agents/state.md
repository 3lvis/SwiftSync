# State Capsule

## Plan

- [x] Inspect the export APIs, tests, and call sites to choose a safe cleanup order
- [x] Implement the export API cleanup in `SwiftSync/**` by removing bulk export and deleting bulk-only tests/benchmarks
- [x] Add tests for container-centric object export naming before changing the library
- [x] Rename object export to `syncContainer.export(_:)` and align internal naming with `export`
- [x] Update docs and planning notes to match the remaining export surface
- [x] Run relevant SwiftSync tests and review the final diff

## Last known state

bulk export removed; object export renamed to `syncContainer.export(_:)`; export tests pass

## Decisions (don't revisit)

- Work on a feature branch because implementation on `master` is disallowed
- Follow library TDD for changes in `SwiftSync/**`
- Decide cleanup order from current code and test usage rather than renaming surfaces blindly
- Remove the bulk export API entirely rather than preserving an internal helper
- Make the public object-export API container-centric for consistency with `sync`

## Files touched

- .agents/state.md
- README.md
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncableMacro.swift
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- SwiftSync/Tests/SwiftSyncMacrosTests/SyncableMacroDiagnosticsTests.swift
