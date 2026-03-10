# State Capsule

## Plan

- [x] Add deeper profiling inside `apply-relationships` for the demo-shaped workload and record the before baseline on the same `sqlite + 10k` benchmark command
- [x] Add or update focused tests for the chosen relationship-path optimization and confirm the expected failure if behavior changes
- [x] Implement the highest-yield `apply-relationships` optimization for the demo-shaped workload
- [x] Run focused tests, `swift test --filter SyncTests`, and the same `sqlite + 10k` demo-shaped benchmark command to verify the before/after delta
- [x] Update project and planning docs with the retained relationship-optimization result

## Last known state

relationship optimization retained on `experiment/demo-shaped-apply-relationships`: baseline `demo-shaped-project-session` was `5029.438 ms` with `apply-relationships: 4883.392 ms`; after adding helper-level profiling plus per-sync-pass identity-map caching in relationship helpers, the same `sqlite + 10k + 1 sample` command measures `802.906 ms` with `apply-relationships: 638.976 ms`, `relationship-apply-to-one-foreign-key: 319.857 ms`, `relationship-apply-to-many-foreign-keys: 314.975 ms`, `relationship-fetch: 547.230 ms`, `relationship-index-by-id: 72.033 ms`; focused profiler test and `swift test --filter SyncTests` are green

## Decisions (don't revisit)

- Use os_signpost in the library and keep the benchmark harness responsible for emitting aggregate phase totals so Instruments and CLI output stay aligned
- The first optimization needs macro support for a concrete identity predicate because generic SwiftData key-path predicates are blocked under strict concurrency
- This branch touches `Core.swift` and `MacrosImplementation/`; iOS regression will run on merge
- Parent-scoped single-item optimization should follow global-identity semantics: if identity is unique, the row can be fetched by identity and moved across parents
- Parent-scoped batch optimization should fetch the current scope via a macro-generated parent predicate and only use identity-targeted fallback fetches for payload rows missing from that scope
- Parent-scoped export should use the same macro-generated parent predicate strategy as the retained batch optimization and keep the fetch-all fallback for manual conformers without the synthesized predicate hook
- Performance follow-ups must capture the same benchmark command before and after any optimization; this SQLite pass is measurement-only and should not change code until the dominant post-optimization bottleneck is clear
- The optimization sequence ends with relationship application work: do not spend the next cycle on `save-context`; finish the performance work by reducing `apply-relationships` in the realistic demo-shaped workload
- This branch is scoped to demo-shaped relationship optimization only; do not divert into `save-context` or additional fetch-path work unless the new deeper profiling disproves the current hotspot
- The highest-yield relationship optimization on this branch is per-sync-pass identity-map caching for related rows; fetched-row caching alone was not enough because the hot helpers kept rebuilding identity dictionaries on every call

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
