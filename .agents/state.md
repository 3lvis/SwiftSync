# State Capsule

## Plan

- [x] Re-run the retained `single-item sync`, `parent-scoped batch sync`, and `parent-scoped export` benchmarks on `sqlite + 10k` with phase profiling
- [x] Compare the resulting phase breakdowns and identify the dominant remaining bottleneck under SQLite
- [x] Update the project and planning docs with the SQLite confirmation results and the next recommended experiment

## Last known state

SQLite confirmation complete at `10k + 1 sample`: `single-item-sync` `13.765 ms` (`fetch-existing-by-identity: 1.797 ms`), `parent-scoped-batch-sync` `16.458 ms` (`save-context: 6.648 ms`, `fetch-existing-by-parent: 2.333 ms`), `export-parent-scope` `14.510 ms` (`export-map: 8.293 ms`, `export-fetch-by-parent: 2.677 ms`); docs updated, next likely target is the still-broad global or demo-shaped SQLite path rather than more scoped fetch narrowing

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned
- The first optimization needs macro support for a concrete identity predicate because generic SwiftData key-path predicates are blocked under strict concurrency
- This branch touches `Core.swift` and `MacrosImplementation/`; iOS regression will run on merge
- Parent-scoped single-item optimization should follow global-identity semantics: if identity is unique, the row can be fetched by identity and moved across parents
- Parent-scoped batch optimization should fetch the current scope via a macro-generated parent predicate and only use identity-targeted fallback fetches for payload rows missing from that scope
- Parent-scoped export should use the same macro-generated parent predicate strategy as the retained batch optimization and keep the fetch-all fallback for manual conformers without the synthesized predicate hook
- Performance follow-ups must capture the same benchmark command before and after any optimization; this SQLite pass is measurement-only and should not change code until the dominant post-optimization bottleneck is clear

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
