# Fetch Strategy Under Load

## Why this matters

SwiftSync is supposed to save adopters from building and maintaining manual sync logic themselves. That only matters if the library is not just correct, but fast enough to feel like a good trade.

This document answers the practical question:

"How fast is SwiftSync right now on realistic workloads?"

It focuses on the current retained performance story, not every implementation idea that was explored along the way.

## Current headline

For the current library code on this branch, the strongest benchmark signal is still the demo-shaped SQLite scenario:

- `sqlite + 1k` total rows: about `713 ms` median
- `sqlite + 10k` total rows: about `803 ms` in the latest profiled run

That scenario simulates a realistic app session:

- project-scoped task list sync
- single task detail update with assignee, tags, and watchers
- single user update
- scoped export for the same project

This is the benchmark that best answers what a real app flow feels like, because it combines the operations a task-driven app would actually perform instead of measuring one helper in isolation.

## What improved

The major retained optimization was a sync-pass-local relationship lookup cache.

Before that optimization, the same demo-shaped scenario measured:

- `sqlite + 1k`: about `4821 ms`
- `sqlite + 10k`: about `49842 ms`

After the optimization, the current retained numbers are:

- `sqlite + 1k`: about `713 ms`
- `sqlite + 10k`: about `803 ms` in the latest profiled run

That is the important story:

- a realistic `1k` session moved from multi-second to sub-second
- a realistic `10k` session moved from nearly `50s` to about `0.8s`

This is the performance work that actually stayed in the library because it produced a large, user-visible gain.

## Current operating picture

The benchmark harness also measures isolated paths so the realistic scenario can be interpreted correctly.

SQLite baseline findings across `1k`, `10k`, and `50k` rows showed:

- global batch sync scales with total table size:
  about `74 ms`, `741 ms`, `3919 ms`
- single-item sync still scales strongly with total table size:
  about `16 ms`, `143 ms`, `694 ms`
- parent-scoped batch sync with a fixed `100`-row scope still scales with total child-table size:
  about `29 ms`, `212 ms`, `1099 ms`
- parent-scoped export shows the same pattern:
  about `28 ms`, `211 ms`, `1073 ms`
- to-one relationship resolution scales mainly with related-table size:
  about `17 ms`, `161 ms`, `860 ms`

Repeated SQLite runs at `10k` and `50k` kept median and max relatively close, which means the slowdown pattern looks structural rather than noisy.

After phase profiling was added, the first retained follow-up optimization targeted the single-item path only.

On the verified `memory + 1k + 1 sample` benchmark:

- before: about `14.298 ms`, dominated by `fetch-existing: 11.870 ms`
- after: about `1.898 ms`, with `fetch-existing-by-identity: 0.774 ms`

That change matters because it confirmed the instrumentation was pointing at a real bottleneck, not just noise: when the full-table fetch was replaced by an identity-targeted fetch, the single-item path dropped by about `87%` in the measured run.

The next retained follow-up extended the same macro-driven idea to parent-scoped paths.

On the verified `memory + 1k + 1 sample` parent-scoped batch benchmark:

- before: about `30.872 ms`, dominated by `fetch-existing: 13.759 ms`
- after: about `14.155 ms`, with `fetch-existing-by-parent: 2.006 ms`

That change mattered for two reasons:

- it cut the measured parent-scoped batch path by about `54%`
- it showed that macro-generated concrete parent predicates can remove full-table fetch plus in-memory scope filtering from the retained path, not just single-item lookup

The next retained follow-up applied the same macro-generated parent predicate to parent-scoped export.

On the verified `memory + 1k + 1 sample` parent-scoped export benchmark:

- before: about `32.289 ms`, dominated by `export-fetch: 16.154 ms`
- after: about `14.229 ms`, with `export-fetch-by-parent: 2.062 ms`

That change mattered for two reasons:

- it cut the measured parent-scoped export path by about `56%`
- it removed the retained `export-fetch` plus `export-filter-scope` pattern for macro-backed parent-scoped models

Those wins also hold under SQLite-backed `10k` runs, which is the more important confirmation for real app caches.

On verified `sqlite + 10k + 1 sample` runs:

- `single-item-sync`: about `13.765 ms`
  with `fetch-existing-by-identity: 1.797 ms` and `save-context: 0.759 ms`
- `parent-scoped-batch-sync`: about `16.458 ms`
  with `fetch-existing-by-parent: 2.333 ms` and `save-context: 6.648 ms`
- `export-parent-scope`: about `14.510 ms`
  with `export-fetch-by-parent: 2.677 ms`, `export-map: 8.293 ms`, and `export-sort: 3.134 ms`

That confirmation changes the remaining bottleneck picture:

- the retained scoped fetch narrowing still matters under SQLite
- parent-scoped batch sync is no longer dominated by broad fetch cost; `save-context` is now heavier
- parent-scoped export is no longer dominated by broad fetch cost; object mapping and sort now outweigh the scoped fetch

The main conclusion is straightforward:

- SwiftSync is much faster now on realistic relationship-heavy workloads than it was before optimization
- the remaining bottlenecks are now tied to relationship fetch plus foreign-key application inside realistic workloads, plus save/materialization cost in broader global paths after fetch narrowing

## What this means for adopters

Today, the benchmark story is strongest for:

- modest local datasets
- relationship-heavy sync flows that benefit from reuse inside one sync pass
- apps where avoiding manual sync machinery is worth more than squeezing every last millisecond out of `10k+` row caches

Today, the benchmark story is weaker for:

- large project/task caches where parent-scoped workflows must stay very fast at `10k+`
- cases where single-row updates are expected to scale mostly with the changed row instead of the total table size

So the honest external message right now is:

- SwiftSync is no longer in the "realistic workload is catastrophically slow" state
- SwiftSync now has a credible realistic-workload story at `10k`, but it is still not ready for a broad "large production cache" performance claim across all paths

## Benchmark harness

The opt-in benchmark suite lives in [FetchStrategyBenchmarkTests.swift](../../SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift).

It covers:

- global batch sync
- single-item sync
- parent-scoped batch sync
- to-one and to-many relationship resolution
- full and parent-scoped export
- mixed workload
- demo-shaped project/task session workload

Run gate:

- `SWIFTSYNC_RUN_BENCHMARKS=1`

Optional selectors:

- `SWIFTSYNC_BENCHMARK_STORES=memory,sqlite`
- `SWIFTSYNC_BENCHMARK_TIERS=1000,10000,50000`
- `SWIFTSYNC_BENCHMARK_RELATIONSHIP_COUNTS=1,10,50`
- `SWIFTSYNC_BENCHMARK_SCOPE_SIZE=100`
- `SWIFTSYNC_BENCHMARK_SAMPLES=3`
- `SWIFTSYNC_BENCHMARK_PROFILE_PHASES=1`

When phase profiling is enabled, each benchmark line also emits `phaseMedianMs=...` so you can see where the wall time is going before opening Instruments.

## Instruments workflow

You do not need an iOS app target to use Instruments here. `swift test` runs the benchmark suite as a macOS process, and Instruments can profile that process directly.

Recommended command for the current headline scenario:

```bash
SWIFTSYNC_RUN_BENCHMARKS=1 \
SWIFTSYNC_BENCHMARK_STORES=sqlite \
SWIFTSYNC_BENCHMARK_TIERS=10000 \
SWIFTSYNC_BENCHMARK_PROFILE_PHASES=1 \
swift test --filter FetchStrategyBenchmarkTests/testDemoShapedScenarioBenchmarks
```

Recommended Instruments setup:

- template: `Time Profiler`
- enable: `Points of Interest`
- profile the `swift test` process launched by the command above

The library now emits `OSSignposter` intervals for the major hot-path phases, including:

- `fetch-existing`
- `fetch-existing-by-identity`
- `fetch-existing-by-parent`
- `filter-scope`
- `build-index`
- `find-existing`
- `apply-fields`
- `apply-relationships`
- `relationship-fetch`
- `delete-missing`
- `save-context`
- `export-fetch`
- `export-fetch-by-parent`
- `export-filter-scope`
- `export-sort`
- `export-map`

Use the benchmark output to identify which phase grows at `10k+`, then use Time Profiler inside that signposted interval to see the exact SwiftData or Swift standard library call stacks consuming the time.

For the retained scoped wins, the next Instruments targets should no longer be broad fetches:

- `save-context` inside parent-scoped batch sync
- `export-map` inside parent-scoped export
- whichever phase dominates the still-broad global batch and demo-shaped SQLite scenarios

The broader SQLite confirmation made the relationship target explicit before the latest retained optimization.

On verified `sqlite + 10k + 1 sample` broader workloads:

- `global-batch-sync`: about `797.134 ms`
  with `save-context: 436.818 ms`, `fetch-existing: 115.286 ms`, and `apply-fields: 103.761 ms`
- `demo-shaped-project-session`: about `5029.438 ms`
  with `apply-relationships: 4883.392 ms`, `relationship-fetch: 512.707 ms`, and `save-context: 73.667 ms`

At that point, that meant:

- the realistic product bottleneck was `apply-relationships`, not fetch
- `save-context` is still large in isolated global batch sync, but it is not the next optimization target
- the next retained performance work should go one level deeper inside relationship application and find which specific helper or relationship mode is consuming the `4.8s`

That deeper relationship attribution and optimization has now also been retained.

On the same verified `sqlite + 10k + 1 sample` demo-shaped benchmark:

- before relationship optimization: about `5029.438 ms`
  with `apply-relationships: 4883.392 ms`
- after relationship optimization: about `802.906 ms`
  with `apply-relationships: 638.976 ms`

The retained change was narrow and pragmatic:

- add helper-level profiling inside relationship application
- keep the existing per-sync-pass fetched-row cache
- add a per-sync-pass identity-map cache so relationship helpers stop rebuilding `[id: row]` dictionaries on every call

The resulting phase picture is much healthier:

- `relationship-fetch: 547.230 ms`
- `relationship-apply-to-one-foreign-key: 319.857 ms`
- `relationship-apply-to-many-foreign-keys: 314.975 ms`
- `relationship-index-by-id: 72.033 ms`
- `save-context: 85.592 ms`

That means the realistic `10k` session is no longer dominated by repeated relationship lookup work. The largest remaining relationship costs are now the one-time related-row fetches plus the actual foreign-key application work.

## Rejected experiment

One follow-up experiment added model-provided identity and scoped fetch-descriptor hooks.

It improved the headline scenario only modestly:

- `sqlite + 1k`: about `713 ms` -> about `671 ms`
- `sqlite + 10k`: about `6943 ms` -> about `6541 ms`

That `10k` gain was about `5.8%`, which was too small to justify the extra API surface and model complexity, so that path was removed from the library.

## Follow-up experiments that were also rejected

Several Milestone 3 follow-ups were tried after the fetch-descriptor path and were also removed.

Parent-scoped scope-first diffing remains the highest-upside idea in theory, but it is currently blocked by SwiftData limits:

- the current scoped sync APIs accept arbitrary relationship key paths
- SwiftData rejects the generic `row[keyPath: ...]` predicate shape needed to turn those into scope-first fetches

So that path is not currently implementable as a clean internal optimization without broader API or model changes.

The next internal experiments were measured and rejected:

- context-local target-row cache for repeated syncs in one `ModelContext`
  `sqlite + 1k`: about `713 ms` -> about `664 ms`
  `sqlite + 10k`: about `6943 ms` -> about `6638 ms`
  Result: about `4.4%` gain at `10k`, too small to justify the added cache state and coherence risk.

- delete-planning fetch shaping via `propertiesToFetch`
  `sqlite + 1k`: about `713 ms` -> about `719 ms`
  `sqlite + 10k`: about `6943 ms` -> about `7379 ms`
  Result: regression, rejected.

- identifier-first delete planning with targeted model rehydration
  `sqlite + 1k`: about `713 ms` -> about `736 ms`
  `sqlite + 10k`: about `6943 ms` -> about `7174 ms`
  Result: regression, rejected.

These trials matter because they narrow the remaining space:

- the obvious internal fetch-narrowing variants have now either been blocked by SwiftData or measured as low-yield
- the retained performance story is still the relationship-cache improvement, not a broader table-scaling fix

## Retained macro-enabled optimization

The first retained fetch-narrowing win after instrumentation was intentionally narrow:

- optimize `sync(item:as:in:)` for models whose sync identity is globally unique
- keep the old full-table fallback for non-unique identities and hand-written conformances without an explicit predicate hook

The implementation detail that made this possible is important:

- the generic SwiftData predicate shape using `row[keyPath: ...]` is still blocked in the general case
- but macro-generated models can synthesize a concrete identity predicate because the macro knows the literal identity property at expansion time

That changes the optimization strategy going forward:

- macro-backed specialization is now a practical tool, not something to avoid
- broader generic predicate shaping is still constrained by SwiftData
- parent-scoped and export fast paths may need the same style of model-generated hook or narrowly specialized API surface

That is no longer just a theory. A retained parent-scoped batch optimization now uses a macro-generated concrete parent predicate to fetch the current scope directly, and only falls back to identity-targeted lookup when a globally unique row is missing from that scope.

## Current status

The honest status on this branch is:

- SwiftSync has a strong retained improvement for realistic relationship-heavy workloads because of the sync-pass-local relationship lookup cache
- SwiftSync now also has retained fetch-narrowing wins for single-item sync and parent-scoped batch sync on macro-backed models
- SwiftSync still has structural costs in larger SQLite-backed global paths and demo-shaped workloads
- the optimized scoped paths now point at second-order costs such as `save-context` and `export-map`
- the realistic demo-shaped workload is no longer dominated by repeated relationship dictionary rebuilds; the remaining work is more evenly split across relationship fetch, foreign-key application, save, export mapping, and global batch costs
- the most obvious internal Milestone 3 follow-ups have now been tried and rejected

That means the next meaningful gain likely requires one of:

- broader API or model changes that make scoped predicates expressible
- a much narrower specialized fast path tied to `ParentScopedModel.parentRelationship`
- or more macro-generated concrete predicate hooks for paths where the generic form is blocked
- or accepting the current operating envelope as the product boundary and documenting it clearly

## Next likely wins
The remaining directions that still look conceptually promising are:

- special-case parent-scoped authoritative sync around scope-level diffing instead of full-table reconciliation
- separate delete planning from full row materialization
- narrow parent-scoped export by scope-first ordering instead of fetch-all-then-filter

But after the rejected experiments above, none of these should be treated as a straightforward internal optimization. They now look like higher-risk work items that need either a new enabling mechanism from SwiftData or a willingness to narrow or evolve the library API.
