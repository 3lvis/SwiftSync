# State Capsule

## Plan

- [x] Add tests that pin the parent-scoped single-item fast path for unique identities, fallback behavior for non-unique/manual conformers, and move-across-parent semantics
- [x] Implement an identity-targeted fetch path for parent-scoped single-item sync where the sync identity is unique
- [x] Run focused tests and the parent-scoped single-item benchmark with phase profiling to verify the fetch phase changes

## Last known state

`swift test --filter SyncTests` green; new `testParentScopedSingleItemSyncBenchmarks` benchmark green with phase output showing `fetch-existing-by-identity: 0.365 ms` and total `2.404 ms` on the verified `memory + 1k + 1 sample` run

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned
- The first optimization needs macro support for a concrete identity predicate because generic SwiftData key-path predicates are blocked under strict concurrency
- This branch touches `Core.swift` and `MacrosImplementation/`; iOS regression will run on merge
- Parent-scoped single-item optimization should follow global-identity semantics: if identity is unique, the row can be fetched by identity and moved across parents

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
- SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift
