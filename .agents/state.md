# State Capsule

## Plan

- [x] Add tests that pin the single-item sync fast path for unique identities and fallback path for non-unique identities
- [x] Implement an identity-targeted fetch path for single-item sync where the sync identity is unique
- [x] Run focused tests and the single-item benchmark with phase profiling to verify the fetch phase changes

## Last known state

`swift test --filter SyncTests` green; profiled benchmark command green and changed single-item phase output from `fetch-existing` to `fetch-existing-by-identity`, with total median dropping from about `14.298 ms` to about `1.898 ms` in the verified `memory + 1k + 1 sample` run

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned
- The first optimization needs macro support for a concrete identity predicate because generic SwiftData key-path predicates are blocked under strict concurrency
- This branch touches `Core.swift` and `MacrosImplementation/`; iOS regression will run on merge

## Files touched

- .agents/state.md
- SwiftSync/Sources/SwiftSync/SyncPerformanceProfiler.swift
- SwiftSync/Sources/SwiftSync/API.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
- docs/project/fetch-strategy-under-load.md
- docs/planning/performance-attribution-follow-ups.md
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- SwiftSync/Sources/SwiftSync/SyncableMacro.swift
- SwiftSync/Tests/SwiftSyncTests/SyncTests.swift
