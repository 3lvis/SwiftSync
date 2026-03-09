# State Capsule

## Plan

- [x] Review the fetch-strategy hotspots and define the benchmark harness shape in code.
- [x] Add an opt-in SwiftSync benchmark suite covering global sync, parent-scoped sync, relationship resolution, and export.
- [x] Add a benchmark runner/documentation path so the suite can be executed intentionally without slowing normal tests.
- [x] Run the benchmark suite at least once in its reduced default configuration to verify it works end to end.
- [x] Update the planning doc with the implemented harness details and any practical constraints discovered during implementation.
- [x] Run Milestone 1 SQLite-backed baseline benchmarks at 1k, 10k, and 50k tiers and summarize the main hotspots.
- [~] Add Milestone 2 repeated-run reporting and a mixed-workload benchmark that is more representative than isolated path timings — reduced sqlite/1k verification completed; larger repeated runs still pending.

## Last known state

Milestone 2 partially implemented; benchmark summaries now report samples/median/max and include a mixed-session workload; reduced sqlite/1k verification passed

## Decisions (don't revisit)

- Strict TDD applies because the work is in `SwiftSync/**`.
- The first implementation pass is benchmark instrumentation only, not fetch-strategy optimization.
- Keep benchmark execution opt-in so normal `swift test` remains fast.
- Avoid inventing performance thresholds before measurements exist; collect evidence first.

## Files touched

- .agents/state.md
- docs/planning/fetch-strategy-under-load.md
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
