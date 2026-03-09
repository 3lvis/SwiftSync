# State Capsule

## Plan

- [x] Review the fetch-strategy hotspots and define the benchmark harness shape in code.
- [x] Add an opt-in SwiftSync benchmark suite covering global sync, parent-scoped sync, relationship resolution, and export.
- [x] Add a benchmark runner/documentation path so the suite can be executed intentionally without slowing normal tests.
- [x] Run the benchmark suite at least once in its reduced default configuration to verify it works end to end.
- [x] Update the planning doc with the implemented harness details and any practical constraints discovered during implementation.
- [x] Run Milestone 1 SQLite-backed baseline benchmarks at 1k, 10k, and 50k tiers and summarize the main hotspots.
- [x] Add Milestone 2 repeated-run reporting and a mixed-workload benchmark that is more representative than isolated path timings.
- [x] Add a sync-pass-local relationship lookup cache and apply it to relationship helpers.
- [x] Re-run the demo-shaped scenario benchmark to measure the first optimization pass.
- [x] Decide whether parent-scoped fetch narrowing is still needed after the relationship-cache pass.
- [x] Add model-provided identity/scoped fetch descriptors and thread them through sync/export paths.
- [x] Re-run focused tests and headline benchmarks to measure the narrowing pass.
- [~] Add generated identity-based fetch descriptors for default `@Syncable` models so narrowing applies without handwritten hooks.
- [ ] Re-run the headline scenario after macro-generated identity narrowing.
- [ ] Decide the next Milestone 3 optimization based on the updated scenario timings.

## Last known state

Parent-scope/identity hook pass is verified; focused tests are green and the demo-shaped SQLite scenario moved from ~713 ms to ~671 ms at 1k and from ~6943 ms to ~6541 ms at 10k; next step is automatic identity narrowing for default `@Syncable` models

## Decisions (don't revisit)

- Strict TDD applies because the work is in `SwiftSync/**`.
- The first implementation pass is benchmark instrumentation only, not fetch-strategy optimization.
- Keep benchmark execution opt-in so normal `swift test` remains fast.
- Avoid inventing performance thresholds before measurements exist; collect evidence first.
- Generic `#Predicate` construction cannot use arbitrary key-path access, so narrowing needs model-provided concrete descriptors rather than a generic key-path predicate builder.
- The model-provided narrowing hooks work, but the 10k scenario improvement is modest enough that they should be synthesized for default `@Syncable` models instead of remaining purely opt-in.

## Files touched

- .agents/state.md
- docs/planning/fetch-strategy-under-load.md
- SwiftSync/Sources/SwiftSync/API.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncTests.swift
