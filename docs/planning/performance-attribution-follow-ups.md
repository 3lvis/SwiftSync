# Performance Attribution Follow-ups

## Open items

- [ ] Re-run the `sqlite + 10k` demo-shaped benchmark with phase profiling enabled and capture the top 3 phases by median time
- [ ] Run the profiled `sqlite + 10k` demo-shaped benchmark under Instruments Time Profiler with Points of Interest and record the hottest SwiftData and Swift call stacks inside the dominant phase
- [ ] Compare `memory` vs `sqlite` phase output at `1k`, `10k`, and `50k` for the remaining broad global paths to separate SwiftData table-scan cost from persistence cost
- [ ] Evaluate whether repeated `context.save()` calls are materially expensive after fetch narrowing and only then consider save batching or save elision
- [ ] Document the current product boundary if scoped predicate fast paths remain blocked by generic SwiftData predicate limitations
- [ ] Determine whether `save-context` in parent-scoped batch sync is a real optimization target or just a fixed floor compared with the remaining global bottlenecks
- [ ] Determine whether `export-map` can be reduced materially enough to matter, or whether effort should move directly to the broader global and demo-shaped SQLite paths

## Current bottlenecks

The initial verified benchmark signal was:

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

That bottleneck has now been improved for `sync(item:as:in:)` on macro-backed models with globally unique identities.

The verified post-change benchmark signal for the same `memory + 1k + 1 sample` run is:

- total: about `1.898 ms`
- `fetch-existing-by-identity`: about `0.774 ms`
- `save-context`: about `0.496 ms`

The remaining structural issue is that several other sync and export paths still fetch the whole table and then filter or search in memory.

The next verified retained benchmark signal is the parent-scoped batch path on the same `memory + 1k + 1 sample` shape:

- before: about `30.872 ms`
- after: about `14.155 ms`
- retained phase shift: `fetch-existing` -> `fetch-existing-by-parent`

The next verified retained benchmark signal is the parent-scoped export path on the same `memory + 1k + 1 sample` shape:

- before: about `32.289 ms`
- after: about `14.229 ms`
- retained phase shift: `export-fetch` + `export-filter-scope` -> `export-fetch-by-parent`

That means the next likely wins are no longer the parent-scoped item, parent-scoped batch, or parent-scoped export paths. The focus should now move to larger SQLite-backed scenarios and whichever remaining paths still perform broad fetches.

The SQLite confirmation run for the retained scoped wins is now also in hand on `sqlite + 10k + 1 sample`:

- `single-item-sync`: about `13.765 ms`
  phases: `fetch-existing-by-identity: 1.797 ms`, `save-context: 0.759 ms`
- `parent-scoped-batch-sync`: about `16.458 ms`
  phases: `fetch-existing-by-parent: 2.333 ms`, `save-context: 6.648 ms`
- `export-parent-scope`: about `14.510 ms`
  phases: `export-fetch-by-parent: 2.677 ms`, `export-map: 8.293 ms`, `export-sort: 3.134 ms`

That means the retained scoped fetch narrowing is confirmed under SQLite, and the next likely wins are no longer additional scoped fetch-path experiments. The focus should now move to:

- the still-broad global and demo-shaped SQLite scenarios
- `save-context` if it remains significant after the broader paths are narrowed
- `export-map` only if it becomes meaningfully visible in real workloads

## Improvement direction

The first retained improvement was fetch narrowing through a macro-generated identity predicate, not micro-optimizing field application.

That means:

- retained macro-generated concrete predicates should be preferred for any remaining hot path where the generic SwiftData predicate form is blocked
- the next work should be driven by fresh `sqlite + 10k` phase data rather than more memory-only fetch narrowing on already-optimized scoped paths
- once a path is no longer dominated by broad fetch cost, the next experiment should target the new top phase only if that phase is material in the larger SQLite-backed workload the product actually cares about

Only after fetch narrowing should we spend time on `save-context`, because the current measurement says fetch dominates by a wide margin.

The important implementation lesson from the first experiment is:

- macro-generated concrete predicate hooks are a practical optimization tool in this codebase
- generic SwiftData predicate shaping is still blocked in places where the code only has an abstract relationship or identity key path

## SQLite scope

There may be SQLite-related gains, but they are secondary until we prove the main bottleneck is inside persistence rather than table-wide fetch shape.

In scope for this repo:

- verifying whether SQLite magnifies the same `fetch-existing` bottleneck seen in memory
- using Instruments to see whether the hot stacks under `fetch-existing` are SwiftData query materialization, SQLite reads, or both
- reducing SQLite work indirectly by narrowing fetches, reducing row materialization, and avoiding fetch-all patterns

Probably out of scope for now:

- low-level SQLite tuning such as PRAGMA changes, index management outside what SwiftData generates, custom SQL, or store-engine-specific hacks

Those are not the right first move while the library still has obvious fetch-all behavior in its own code.
