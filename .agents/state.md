# State Capsule

## Plan

- [x] Add benchmark-reporting tests that pin the new phase breakdown output and profiler enablement behavior
- [x] Implement benchmark phase profiling and os_signpost instrumentation across sync and export paths
- [x] Document how to profile the benchmark test process with Instruments and the new signposts
- [x] Run focused SwiftSync tests to verify the new profiler output and instrumentation wiring

## Last known state

`swift test --filter BenchmarkProfilingSupportTests` green; `swift test --filter SyncTests` green; benchmark verification command with `SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_PROFILE_PHASES=1 ... swift test --filter FetchStrategyBenchmarkTests/testSingleItemSyncBenchmarks` green and emits phase medians

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned

## Files touched

- .agents/state.md
- SwiftSync/Sources/SwiftSync/SyncPerformanceProfiler.swift
- SwiftSync/Sources/SwiftSync/API.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
- docs/project/fetch-strategy-under-load.md
- docs/planning/performance-attribution-follow-ups.md
