# State Capsule

## Plan

- [x] Run `global batch sync` and `demo-shaped scenario` benchmarks on `sqlite + 10k` with phase profiling
- [x] Compare the resulting phase breakdowns and identify the dominant remaining bottleneck under realistic broader workloads
- [x] Update the project and planning docs with the broader SQLite results and the next recommended experiment

## Last known state

broader SQLite profiling complete at `10k + 1 sample`: `global-batch-sync` `797.134 ms` with `save-context: 436.818 ms`, `fetch-existing: 115.286 ms`, `apply-fields: 103.761 ms`; `demo-shaped-project-session` `5029.438 ms` with `apply-relationships: 4883.392 ms`, `relationship-fetch: 512.707 ms`, `save-context: 73.667 ms`; docs updated, and the next retained optimization target is `apply-relationships`, not `save-context`

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned
- The first optimization needs macro support for a concrete identity predicate because generic SwiftData key-path predicates are blocked under strict concurrency
- This branch touches `Core.swift` and `MacrosImplementation/`; iOS regression will run on merge
- Parent-scoped single-item optimization should follow global-identity semantics: if identity is unique, the row can be fetched by identity and moved across parents
- Parent-scoped batch optimization should fetch the current scope via a macro-generated parent predicate and only use identity-targeted fallback fetches for payload rows missing from that scope
- Parent-scoped export should use the same macro-generated parent predicate strategy as the retained batch optimization and keep the fetch-all fallback for manual conformers without the synthesized predicate hook
- Performance follow-ups must capture the same benchmark command before and after any optimization; this SQLite pass is measurement-only and should not change code until the dominant post-optimization bottleneck is clear
- The optimization sequence ends with relationship application work: do not spend the next cycle on `save-context`; finish the performance work by reducing `apply-relationships` in the realistic demo-shaped workload

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
