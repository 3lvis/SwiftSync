# State Capsule

## Plan

Performance-attribution follow-ups (from docs/planning/performance-attribution-follow-ups.md).
Benchmarks now runnable on Xcode 26.5 / Swift 6.3.2 (test target compiles after the isolation refactor, merged to master in c4973c2).

- [ ] item 2: re-run demo-shaped sqlite+10k SAMPLES=5, confirm the retained relationship win is stable (not a single-run outlier)
- [ ] item 3: compare memory vs sqlite phase output at 1k/10k/50k for the remaining broad global paths (global-batch-sync, single-item-sync)
- [ ] item 1: Instruments Time Profiler + Points of Interest on sqlite+10k demo-shaped; record hottest stacks inside `relationship-fetch` (signposts already emit in SyncPerformanceProfiler.swift via OSSignposter)
- [ ] item 4: write the product-boundary section into the planning doc from items 1-3 data, then clear/remove the doc

## Last known state

Branch fresh off master. Toolchain + swift-format work merged to master (c4973c2). No perf items started yet.

## Decisions (don't revisit)

- Benchmark harness: FetchStrategyBenchmarkTests with env vars SWIFTSYNC_RUN_BENCHMARKS=1, SWIFTSYNC_BENCHMARK_STORES, SWIFTSYNC_BENCHMARK_TIERS, SWIFTSYNC_BENCHMARK_SAMPLES, SWIFTSYNC_BENCHMARK_PROFILE_PHASES.
- Run `swift test` benchmarks in the FOREGROUND or via background-to-file; piping through grep buffers output to 0 bytes until completion.
- Record before/after on the same command per AGENTS.md perf rule.

## Files touched

- .agents/state.md (new for this branch)
