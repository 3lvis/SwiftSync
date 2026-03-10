# State Capsule

## Plan

- [x] Record the before-change baseline for parent-scoped batch sync with phase profiling
- [x] Add tests that pin the parent-scoped batch fast path for macro-backed models and fallback behavior for manual conformers
- [x] Implement a parent-targeted fetch path for parent-scoped batch sync using a macro-generated concrete parent predicate and identity fallback for global rows
- [x] Run focused tests, `swift test --filter SyncTests`, and the same parent-scoped batch benchmark command to verify the before/after delta

## Last known state

parent-scoped batch baseline recorded at `30.872 ms` with `fetch-existing: 13.759 ms`; after the macro-driven parent predicate change the same benchmark measures `14.155 ms` with `fetch-existing-by-parent: 2.006 ms`; `swift test --filter SyncTests` green

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned
- The first optimization needs macro support for a concrete identity predicate because generic SwiftData key-path predicates are blocked under strict concurrency
- This branch touches `Core.swift` and `MacrosImplementation/`; iOS regression will run on merge
- Parent-scoped single-item optimization should follow global-identity semantics: if identity is unique, the row can be fetched by identity and moved across parents
- Parent-scoped batch optimization should fetch the current scope via a macro-generated parent predicate and only use identity-targeted fallback fetches for payload rows missing from that scope

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
- AGENTS.md
