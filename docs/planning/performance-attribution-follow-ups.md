# Performance Attribution Follow-ups

## Open items

- [ ] Narrow `relationship-fetch` to only the referenced related rows via a macro-generated multi-identity (`IN`) predicate; collect the union of referenced IDs per sync pass, cache per type as today, and fall back to a full fetch above a threshold (SQLite param limits). Measure on the `demo-shaped-project-session` benchmark before/after.

## Next optimization target: narrow `relationship-fetch` (why + how)

**The gap (confirmed by the fixture, not speculative):** both relationship-resolution paths fetch the entire related table to resolve however few IDs the payload references — `try context.fetch(FetchDescriptor<Model>())` with no predicate (`Core.swift` `SyncRelationshipLookupCache.rows(for:in:)` and `syncFetchRelatedRows(_:in:)`). The per-pass `SyncRelationshipLookupCache` only ensures this runs once per type per pass; it does not narrow *what* is fetched.

In the demo-shaped benchmark (`FetchStrategyBenchmarkTests.testDemoShapedScenarioBenchmarks`), at the 10k tier the related tables hold 10,000 rows but the payload references only ~20 IDs total (`tag_ids: Array(1...10)`, `watcher_ids`: 10, `assignee_id`: 1). So the ~547 ms `relationship-fetch` materializes 10,000 rows to use ~20 — the same fetch-all-then-filter-in-memory pattern already beaten on the `fetch-existing-by-identity` path.

**Why this, not Instruments:** the layer question (SwiftData faulting vs SQLite reads vs model materialization) is moot while the fetch is unbounded — over-fetching 10k rows to use 20 is wasteful at every layer, and the fix does not depend on the answer. The macro already emits `Model.syncIdentityPredicate(matching:)` for the single-identity fast path (`API.swift`); the natural move is an `IN`-predicate variant for related-row resolution.

**Caveat — the win is reference-density dependent:** narrowing helps only when referenced IDs are a small subset of the related table (K ≪ N), which the demo fixture is and detail/list screens generally are. If a pass references most of the table, an `IN` over thousands of IDs won't help and risks SQLite's parameter limit — hence narrow to the per-pass union of referenced IDs and keep a full-fetch fallback above a threshold.

**Instruments is now the fallback, not the gate:** run it only if the `IN`-predicate narrowing fails to move `relationship-fetch` on the demo benchmark. That outcome would prove the residual cost is materializing rows we genuinely need — and only then does layer attribution decide the next move.

**Exact Instruments steps if it comes to that:**

1. The signposts already exist — `SyncPerformanceProfiler` emits `OSSignposter` intervals named `SwiftSyncPhase` (subsystem `SwiftSync`, category `Performance`), with the phase name as the interval message, so `relationship-fetch` shows up as a labelled interval.
2. Record headlessly with the bundled toolchain:

   ```
   SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_PROFILE_PHASES=1 \
   SWIFTSYNC_BENCHMARK_STORES=sqlite SWIFTSYNC_BENCHMARK_TIERS=10000 SWIFTSYNC_BENCHMARK_SAMPLES=1 \
   xcrun xctrace record --template 'Time Profiler' \
     --launch -- $(swift build --show-bin-path)/SwiftSyncPackageTests.xctest
   ```

   or attach the Time Profiler + os_signpost instruments in Instruments.app to the test run and filter to the `SwiftSyncPhase` / `relationship-fetch` interval.
3. Inside the `relationship-fetch` interval, capture the hottest stacks and classify them: SwiftData relationship fault/fetch vs SQLite read vs model materialization. That classification is the deliverable — it decides whether the next optimization targets fetch shaping, batching, or materialization.

## Product boundary (measured 2026-06-10, Xcode 26.5 / Swift 6.3.2)

Confirmed with multi-sample runs on the same `FetchStrategyBenchmarkTests` harness.

Demo-shaped `sqlite + 10k`, 5 samples — the retained relationship win is stable, not a single-run outlier:

- total: median `744 ms`, max `783 ms` (prior single-run was about `803 ms`)
- `apply-relationships`: about `596 ms` (dominant), with `relationship-fetch` about `509 ms` as the largest sub-phase — this is the next attribution target if the demo-shaped path is optimized further

Global paths, `memory` vs `sqlite`, 3 samples — persistence is **not** the bottleneck (stores are within noise of each other), so the cost is SwiftData model-layer work, not the store engine:

| case | tier | memory median | sqlite median |
| --- | --- | --- | --- |
| `global-batch-sync` | 1k | `78 ms` | `75 ms` |
| `global-batch-sync` | 10k | `804 ms` | `780 ms` |
| `global-batch-sync` | 50k | `3997 ms` | `4160 ms` |
| `single-item-sync` | 1k | `2.3 ms` | `2.2 ms` |
| `single-item-sync` | 10k | `12.6 ms` | `12.9 ms` |
| `single-item-sync` | 50k | `59 ms` | `58 ms` |

For `global-batch-sync` at `10k` the phase split is `save-context` about `410 ms` (~52%), `fetch-existing` (full-table) about `115 ms`, `apply-fields` about `100 ms` — all scaling roughly linearly with row count. `single-item-sync` stays cheap (≤ `59 ms` even at `50k`).

Boundary conclusions:

- Low-level SQLite tuning (PRAGMA, custom SQL) is confirmed out of scope: `sqlite ~= memory`.
- The realistic demo-shaped bottleneck is relationship work (`relationship-fetch`); the isolated global-batch bottleneck is `save-context`, which is explicitly **not** the next target for the realistic workload.
- Single-item and scoped paths are already fast and not worth further fetch-narrowing.

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
- the dominant phase in the realistic demo-shaped workload
- `export-map` only if it becomes meaningfully visible in real workloads after relationship work is improved

The broader SQLite confirmation run is now also in hand on `sqlite + 10k + 1 sample`:

- `global-batch-sync`: about `797.134 ms`
  phases: `save-context: 436.818 ms`, `fetch-existing: 115.286 ms`, `apply-fields: 103.761 ms`
- `demo-shaped-project-session`: about `5029.438 ms`
  phases: `apply-relationships: 4883.392 ms`, `relationship-fetch: 512.707 ms`, `save-context: 73.667 ms`

That changes the priority order decisively:

- the highest-value remaining work is inside `apply-relationships`
- `save-context` is explicitly not the next optimization target, even though it is large in isolated global batch sync
- further fetch narrowing is now lower value than deeper relationship-work attribution in the realistic workload

The retained relationship optimization run is now also in hand on the same `sqlite + 10k + 1 sample` demo-shaped benchmark:

- before: about `5029.438 ms`
  phases: `apply-relationships: 4883.392 ms`, `relationship-fetch: 512.707 ms`, `save-context: 73.667 ms`
- after: about `802.906 ms`
  phases: `apply-relationships: 638.976 ms`, `relationship-fetch: 547.230 ms`, `relationship-apply-to-one-foreign-key: 319.857 ms`, `relationship-apply-to-many-foreign-keys: 314.975 ms`, `relationship-index-by-id: 72.033 ms`, `save-context: 85.592 ms`

That changes the priority order again:

- the dominant realistic bottleneck is no longer broad relationship application
- the retained win came from per-sync-pass identity-map caching on top of the existing related-row fetch cache
- the next useful attribution target is `relationship-fetch` itself, not `save-context`

## Improvement direction

The first retained improvement was fetch narrowing through a macro-generated identity predicate, not micro-optimizing field application.

That means:

- retained macro-generated concrete predicates should be preferred for any remaining hot path where the generic SwiftData predicate form is blocked
- the next work should be driven by fresh `sqlite + 10k` phase data rather than more memory-only fetch narrowing on already-optimized scoped paths
- once a path is no longer dominated by broad fetch cost, the next experiment should target the new top phase only if that phase is material in the larger SQLite-backed workload the product actually cares about
- the retained relationship win came from removing repeated identity-map rebuilds inside relationship helpers
- do not spend the next optimization cycle on `save-context`; it is still not the dominant real-workload bottleneck

The important implementation lesson from the first experiment is:

- macro-generated concrete predicate hooks are a practical optimization tool in this codebase
- generic SwiftData predicate shaping is still blocked in places where the code only has an abstract relationship or identity key path

## SQLite scope

There may be SQLite-related gains, but they are secondary until we prove the main bottleneck is inside persistence rather than table-wide fetch shape.

In scope for this repo:

- verifying whether SQLite magnifies the same `fetch-existing` bottleneck seen in memory
- using Instruments to see whether the hot stacks under `relationship-fetch` are SwiftData relationship fetches, SQLite reads, or model materialization overhead
- reducing SQLite work indirectly by narrowing fetches, reducing row materialization, and avoiding fetch-all patterns

Probably out of scope for now:

- low-level SQLite tuning such as PRAGMA changes, index management outside what SwiftData generates, custom SQL, or store-engine-specific hacks

Those are not the right first move while the library still has obvious fetch-all behavior in its own code.
