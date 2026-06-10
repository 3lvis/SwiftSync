# State Capsule

## Plan

Performance-attribution follow-ups (from docs/planning/performance-attribution-follow-ups.md).
Benchmarks now runnable on Xcode 26.5 / Swift 6.3.2 (test target compiles after the isolation refactor, merged to master in c4973c2).

- [x] item 2: demo-shaped sqlite+10k, 5 samples -> median 744ms / max 783ms (vs prior single-run ~803ms). STABLE. apply-relationships 596ms median; relationship-fetch 509ms is the dominant sub-phase -> confirms next target.
- [x] item 3: memory vs sqlite at 1k/10k/50k. FINDING: sqlite ~= memory across all tiers (within noise) -> bottleneck is SwiftData model-layer, NOT persistence. global-batch 10k: save-context ~410ms (52%), fetch-existing ~115ms, apply-fields ~100ms, all linear. single-item fast (<=59ms at 50k).
- [x] item 4: product-boundary section written into planning doc; completed open items pruned (only the optional Instruments item remains)
- [ ] item 1: Instruments Time Profiler + Points of Interest on sqlite+10k demo-shaped (GUI/xctrace; signposts emit via OSSignposter). OPTIONAL/DEFERRED — items 2-3 already answer the doc's questions; phase profiler already names relationship-fetch as dominant. Instruments would only add Swift/SwiftData stack-level detail. Awaiting user decision.

## Last known state

Branch fresh off master. Toolchain + swift-format work merged to master (c4973c2). No perf items started yet.

## Decisions (don't revisit)

- Benchmark harness: FetchStrategyBenchmarkTests with env vars SWIFTSYNC_RUN_BENCHMARKS=1, SWIFTSYNC_BENCHMARK_STORES, SWIFTSYNC_BENCHMARK_TIERS, SWIFTSYNC_BENCHMARK_SAMPLES, SWIFTSYNC_BENCHMARK_PROFILE_PHASES.
- Run `swift test` benchmarks in the FOREGROUND or via background-to-file; piping through grep buffers output to 0 bytes until completion.
- Record before/after on the same command per AGENTS.md perf rule.

## Files touched

- .agents/state.md (new for this branch)
