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
- [x] Remove the rejected fetch-descriptor optimization path from the library and keep only the documented findings.
- [ ] Choose the next high-leverage optimization direction after the rejected-path cleanup.
- [ ] Decide the next Milestone 3 optimization based on the updated scenario timings.

## Last known state

Fetch-descriptor narrowing is rejected and removed from the library; planning doc records the ~5.8% sqlite/10k gain as insufficient, and focused `ParentScoped` tests are green on the cleaned-up codepath

## Decisions (don't revisit)

- Strict TDD applies because the work is in `SwiftSync/**`.
- The first implementation pass is benchmark instrumentation only, not fetch-strategy optimization.
- Keep benchmark execution opt-in so normal `swift test` remains fast.
- Avoid inventing performance thresholds before measurements exist; collect evidence first.
- Generic `#Predicate` construction cannot use arbitrary key-path access, so narrowing needs model-provided concrete descriptors rather than a generic key-path predicate builder.
- The fetch-descriptor narrowing path is not worth keeping as a standalone optimization because the 10k scenario gain is only about 5.8%.
- Changes in `Core.swift` mean iOS regression will run on merge.

## Files touched

- .agents/state.md
- docs/planning/fetch-strategy-under-load.md
- SwiftSync/Sources/SwiftSync/API.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
- SwiftSync/Tests/SwiftSyncMacrosTests/SyncableMacroDiagnosticsTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncTests.swift
