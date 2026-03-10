# State Capsule

## Plan

- [x] Record the before-change baseline for parent-scoped export with phase profiling
- [x] Add tests that pin the parent-scoped export fast path for macro-backed models and fallback behavior for manual conformers
- [x] Implement a parent-targeted fetch path for parent-scoped export using the macro-generated concrete parent predicate
- [x] Run focused tests, `swift test --filter SyncTests`, and the same parent-scoped export benchmark command to verify the before/after delta

## Last known state

parent-scoped export fast path retained and verified: baseline `32.289 ms` (`export-fetch: 16.154 ms`, `export-filter-scope: 3.253 ms`, `export-map: 8.750 ms`, `export-sort: 2.978 ms`) -> after `14.229 ms` (`export-fetch-by-parent: 2.062 ms`, `export-map: 8.333 ms`, `export-sort: 3.469 ms`); `swift test --filter ExportTests` and `swift test --filter SyncTests` are green

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned
- The first optimization needs macro support for a concrete identity predicate because generic SwiftData key-path predicates are blocked under strict concurrency
- This branch touches `Core.swift` and `MacrosImplementation/`; iOS regression will run on merge
- Parent-scoped single-item optimization should follow global-identity semantics: if identity is unique, the row can be fetched by identity and moved across parents
- Parent-scoped batch optimization should fetch the current scope via a macro-generated parent predicate and only use identity-targeted fallback fetches for payload rows missing from that scope
- Parent-scoped export should use the same macro-generated parent predicate strategy as the retained batch optimization and keep the fetch-all fallback for manual conformers without the synthesized predicate hook

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
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
