# Performance Attribution Follow-ups

## Open items

- [ ] Replace full-table fetch in single-item sync with an identity-targeted fetch descriptor and re-measure `single-item-sync`
- [ ] Replace full-table fetch plus in-memory scope filtering in parent-scoped single-item sync with a parent-plus-identity targeted fetch path where SwiftData allows it
- [ ] Prototype a scope-targeted fetch path for parent-scoped batch sync so delete planning and index construction operate on scope rows instead of the full child table
- [ ] Re-run the `sqlite + 10k` demo-shaped benchmark with phase profiling enabled and capture the top 3 phases by median time
- [ ] Run the profiled `sqlite + 10k` benchmark under Instruments Time Profiler with Points of Interest and record the hottest SwiftData call stacks inside `fetch-existing`
- [ ] Compare `memory` vs `sqlite` phase output at `1k`, `10k`, and `50k` to separate SwiftData table-scan cost from persistence cost
- [ ] Evaluate whether scoped export can avoid fetch-all-then-filter by introducing a narrower parent-scoped export fetch path
- [ ] Evaluate whether repeated `context.save()` calls are materially expensive after fetch narrowing and only then consider save batching or save elision
- [ ] Document the current product boundary if scoped predicate fast paths remain blocked by generic SwiftData predicate limitations

## Current bottlenecks

The current verified benchmark signal is from:

`SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_PROFILE_PHASES=1 SWIFTSYNC_BENCHMARK_STORES=memory SWIFTSYNC_BENCHMARK_TIERS=1000 SWIFTSYNC_BENCHMARK_SAMPLES=1 swift test --filter FetchStrategyBenchmarkTests/testSingleItemSyncBenchmarks`

The emitted phase breakdown was:

- `fetch-existing`: about `11.870 ms`
- `save-context`: about `1.142 ms`
- `find-existing`: about `0.429 ms`
- `apply-fields`: about `0.031 ms`
- `normalize-payload`: about `0.021 ms`
- `apply-relationships`: about `0.002 ms`

High-level worst call:

- `context.fetch(FetchDescriptor<Model>())`

Mid-level worst call after that:

- `context.save()`

The main structural issue is that several sync and export paths still fetch the whole table and then filter or search in memory.

## Improvement direction

The first improvement to pursue is fetch narrowing, not micro-optimizing field application.

That means:

- single-item sync should fetch by identity instead of fetch-all-then-scan
- parent-scoped single-item sync should fetch by parent plus identity instead of fetch-all-then-filter-then-scan
- parent-scoped batch sync should operate on scope rows instead of the full child table whenever SwiftData can express the predicate
- scoped export should avoid fetch-all-then-filter if a safe scoped fetch path is possible

Only after fetch narrowing should we spend time on `save-context`, because the current measurement says fetch dominates by a wide margin.

## SQLite scope

There may be SQLite-related gains, but they are secondary until we prove the main bottleneck is inside persistence rather than table-wide fetch shape.

In scope for this repo:

- verifying whether SQLite magnifies the same `fetch-existing` bottleneck seen in memory
- using Instruments to see whether the hot stacks under `fetch-existing` are SwiftData query materialization, SQLite reads, or both
- reducing SQLite work indirectly by narrowing fetches, reducing row materialization, and avoiding fetch-all patterns

Probably out of scope for now:

- low-level SQLite tuning such as PRAGMA changes, index management outside what SwiftData generates, custom SQL, or store-engine-specific hacks

Those are not the right first move while the library still has obvious fetch-all behavior in its own code.
