# Fetch Strategy Under Load

## Why

SwiftSync currently uses simple, deterministic sync flows that often rely on full-table fetches rather than narrowly targeted fetches. Several core paths fetch all rows for a model and then perform matching, filtering, or relationship resolution in memory.

That design may be completely acceptable for the library's intended operating range. It may also become the main scaling constraint once stores grow beyond small demo-sized datasets.

The current problem is not that the strategy is proven wrong. The problem is that its operating envelope is undocumented.

Without explicit validation or an explicit non-goal, adopters are left to guess:

- whether full-table fetches remain acceptable at realistic app sizes
- whether parent-scoped sync remains efficient with large child tables
- whether relationship linking costs stay bounded as related model counts grow
- whether the library is meant for modest local caches rather than large persistent stores

This ambiguity affects adoption decisions more than the raw implementation itself. A clear statement such as “optimized for modest local datasets” is a valid outcome if that is the real design target. A benchmark-backed statement is a valid outcome if larger datasets are intended to be supported.

## What

This work should define the expected performance envelope for the current fetch strategy and identify the evidence needed to support that position.

The goal is to resolve the scaling question in a controlled order:

1. benchmark the current behavior
2. optimize the paths that can be improved cleanly
3. define explicit options or limits for the paths that cannot be improved enough

This keeps the work evidence-driven and avoids speculative rewrites.

For internal engineering, code-path benchmarks are enough to identify hotspots.

For third-party adoption decisions, they are not enough on their own. A prospective user deciding whether SwiftSync fits a large production app will want evidence that is:

- SQLite-backed, not just in-memory
- repeated enough to show stable median and tail behavior
- based on workload mixes, not only isolated single-operation timings
- representative of realistic model graphs and relationship shapes
- explicit about the supported operating envelope rather than implying universal scale readiness

## Milestones

### Milestone 1: Baseline measurement

Build and verify an opt-in benchmark harness, then use it to measure the main fetch-sensitive paths on the
important store shapes and dataset tiers.

This milestone exists to answer:
"Which paths actually scale with total table size, and how badly in SQLite-backed stores?"

### Milestone 2: Representative confidence

Add repeated runs, mixed workloads, and at least one more realistic model graph so the results are useful
for someone evaluating SwiftSync for a larger production app.

This milestone exists to answer:
"Are the measurements representative enough to support an adoption decision, not just an internal optimization pass?"

### Milestone 3: Decisions and docs

Use the measurements to decide what should be optimized, what should remain as-is, and what usage guidance or
limits need to be documented. Then publish the supported operating envelope clearly.

This milestone exists to answer:
"What should an adopter conclude from this work?"

## Open items

- [ ] Complete Milestone 1 by running the benchmark harness across the main SQLite-backed dataset tiers and identifying the true hotspots.
- [ ] Complete Milestone 2 by adding repeated-run and mixed-workload coverage that is credible to a third-party evaluator.
- [ ] Complete Milestone 3 by turning the results into optimization work, documented limits, and a clear support statement.

## Solution shape

- Benchmark first so optimization work is driven by measured cost instead of assumption.
- Optimize the paths that can be narrowed without making the API or implementation brittle.
- Expose clear limits or alternative usage guidance for the paths that must remain scale-sensitive.

## Benchmark plan

Use a dedicated benchmark test file in `SwiftSync/Tests/SwiftSyncTests` with timing helpers based on
`ContinuousClock` or `DispatchTime`, but keep the suite opt-in so normal package tests stay fast.

Implemented harness:

- `SwiftSync/Tests/SwiftSyncTests/FetchStrategyBenchmarkTests.swift`
- opt-in gate: `SWIFTSYNC_RUN_BENCHMARKS=1`
- optional selectors:
  - `SWIFTSYNC_BENCHMARK_STORES=memory,sqlite`
  - `SWIFTSYNC_BENCHMARK_TIERS=1000,10000,50000`
  - `SWIFTSYNC_BENCHMARK_RELATIONSHIP_COUNTS=1,10,50`
  - `SWIFTSYNC_BENCHMARK_SCOPE_SIZE=100`
  - `SWIFTSYNC_BENCHMARK_SAMPLES=3`

Default enabled configuration is intentionally reduced:

- `memory` store only
- `1000` rows only
- relationship counts `1,10,50`
- scope size `100`

That default is for harness verification. The full planning matrix still needs intentional opt-in execution.

The benchmark harness should report:

- wall-clock duration per benchmark case
- row counts for total table size, scoped slice size, and payload size
- store kind (`inMemory` or `sqlite`)
- the specific code path under test
- workload type (`isolated` or `mixed`)

The external-facing benchmark phase should additionally report:

- sample count per case
- median and max duration
- workload description in user-facing terms
- whether the case represents an isolated path or a mixed workload

The first pass should benchmark current behavior before any optimization work. The harness does not
need CI thresholds yet; the immediate output is a reproducible local measurement tool plus a checked-in
summary of results.

## Benchmark matrix

### Store kinds

- `inMemory` to isolate pure library/query-shape overhead
- `sqlite` to capture the cost shape users are more likely to care about in real apps

### Dataset tiers

- 1,000 existing rows: confirms baseline overhead and catches accidental regressions in small stores
- 10,000 existing rows: likely “serious app cache” territory and the first scale tier that should drive decisions
- 50,000 existing rows: stress tier to expose obviously unbounded full-table paths

Do not start with 100,000+ rows. If 50,000 already makes a path clearly unacceptable, larger tiers add runtime
without adding much signal. Add 100,000 only if the 50,000-row results are still ambiguous.

### Payload and scope sizes

- 100-row payloads for “small incremental sync against a large store”
- 1,000-row payloads for “large page/batch sync”
- 100-row parent scope inside a much larger child table for parent-scoped sync
- relationship payloads that touch 1, 10, and 50 related IDs/objects against large related tables

### Benchmark categories

- Authoritative batch sync:
  `sync(payload:)` for a full target slice, where missing rows are part of the measured diff/delete cost
- Incremental update:
  `sync(item:)` for a single-row change against a much larger existing table
- Parent-scoped authoritative sync:
  `sync(payload:parent:relationship:)` for the full parent slice only
- Relationship resolution:
  helpers reached through sync that must resolve linked rows from large related tables
- Export:
  full-model export and parent-scoped export

### Cases to measure first

- Global batch sync of a model with an existing table of 1k / 10k / 50k rows
- Single-item sync against an existing table of 1k / 10k / 50k rows
- Parent-scoped batch sync where the parent owns 100 rows but the full child table is 1k / 10k / 50k rows
- To-one FK resolution against related tables of 1k / 10k / 50k rows
- To-many FK resolution for 10 and 50 related IDs against related tables of 1k / 10k / 50k rows
- To-many nested-object sync for 10 and 50 related objects against related tables of 1k / 10k / 50k rows
- Export of all rows for a model with 1k / 10k / 50k rows
- Parent-scoped export where the exported slice is 100 rows but the full child table is much larger
- Mixed session workload that combines incremental sync, parent-scoped sync, relationship-heavy sync, and scoped export

### Cases needed for third-party confidence

- SQLite-backed `10k` and `50k` runs for the main sync and relationship cases
- repeated-run results for each published case, not just one timing
- a mixed workload simulating a realistic app session:
  small item updates, list syncs, parent-scoped syncs, relationship updates, and read/export pressure
- a realistic graph benchmark with multiple related model types and uneven relationship fan-out
- a clear summary separating:
  supported operating tier,
  stress-tested-but-not-primary tier,
  and out-of-scope scale assumptions

Practical constraint discovered during harness implementation:

- global batch sync is authoritative for the target model table, so a “100-row payload against a 10k-row table”
  primarily measures delete work rather than incremental update cost
- the benchmark harness therefore uses full-slice payloads for global batch sync and reserves incremental-cost
  measurement for `sync(item:)`

## Run order

Run the matrix in stages instead of treating every case as equally urgent:

1. `memory + 1k` to verify harness correctness and get a low-noise baseline
2. `sqlite + 1k` to surface immediate disk-backed cost differences
3. `memory + 10k` to see whether pure fetch/query shape already scales poorly
4. `sqlite + 10k` as the main decision tier for real-world behavior
5. `50k` only for the paths that still look ambiguous or clearly risky after `10k`
6. repeated SQLite runs plus mixed-workload runs for the cases that will be cited in docs or adoption guidance

Do not default to the full `1k + 10k + 50k` by `memory + sqlite` matrix on every iteration. Use the
smaller stages to decide where the expensive runs are worth spending time.

## Expected decision points

The benchmark output should let us sort paths into three buckets:

- clearly acceptable as-is for the measured operating envelope
- worth optimizing internally because a narrower fetch or index can improve them without API changes
- inherently scale-sensitive in SwiftData, which means we should document limits or add explicit caller options

For external communication, those buckets must become an explicit support statement, for example:

- recommended operating tier
- acceptable with caveats
- not a current target envelope

## Notes

- Run benchmarks sequentially, not in parallel, to keep store and cache effects understandable.
- Recreate a fresh store for each benchmark case so one case does not warm the next one.
- Record both seed time and measured operation time, but do not mix them into one number.
- Prioritize `10k` as the main decision tier; `1k` is sanity-check, `50k` is stress validation.
- Verification command for the reduced harness:
  `SWIFTSYNC_RUN_BENCHMARKS=1 swift test --filter FetchStrategyBenchmarkTests`

## Result interpretation

Use the first benchmark pass to answer scaling-shape questions before setting performance targets:

- If `sync(item:)` grows materially with total table size, the lookup/index path is probably too table-wide.
- If parent-scoped sync grows mostly with total child-table size rather than scoped-slice size, parent filtering is a strong candidate for narrowing.
- If relationship-resolution time grows mostly with related-table size for tiny relationship counts, repeated full related-table fetches are the likely hotspot.
- If export grows with total table size, that may be acceptable by design; the question is whether parent-scoped export also pays unnecessary global-table cost.

Do not convert the first results into hard pass/fail thresholds immediately. First use them to identify which paths scale with:

- total table size
- payload or scope size
- relationship membership size

Only after that should the project define a supported operating envelope or regression thresholds.

## External decision bar

If the goal is to help a third party decide whether to adopt SwiftSync for a larger production app, the published results should be able to answer:

- How does SQLite-backed sync behave at `10k` and `50k` rows?
- Does small incremental work scale with the total store size or mostly with the changed slice?
- What are the median and worst-case timings, not just the fastest observed run?
- What workload shape was tested, and how close is it to a real app cache?
- What store sizes and sync patterns are considered in-scope for SwiftSync today?

If the benchmark package cannot answer those questions yet, it should be presented as internal profiling evidence, not as an adoption proof point.

## Milestone 1 findings

Initial SQLite-backed baseline run completed for `1k`, `10k`, and `50k` tiers with:

`SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_STORES=sqlite SWIFTSYNC_BENCHMARK_TIERS=1000,10000,50000 swift test --filter FetchStrategyBenchmarkTests`

High-level findings:

- global batch sync scales roughly with total table size:
  about `74 ms` at `1k`, `741 ms` at `10k`, `3919 ms` at `50k`
- single-item sync also scales strongly with total table size:
  about `16 ms` at `1k`, `143 ms` at `10k`, `694 ms` at `50k`
- parent-scoped batch sync scales with total child-table size even though the scoped slice stays fixed at `100` rows:
  about `29 ms` at `1k`, `212 ms` at `10k`, `1099 ms` at `50k`
- parent-scoped export shows the same pattern:
  about `28 ms` at `1k`, `211 ms` at `10k`, `1073 ms` at `50k`
- relationship resolution cost is dominated by related-table size, not relationship membership count:
  to-one FK resolution is about `17 ms` at `1k`, `161 ms` at `10k`, `860 ms` at `50k`
  to-many FK and nested-object resolution track the same related-table growth curve, while `1`, `10`, and `50` linked rows stay relatively close to each other
- full export is one of the most obviously table-wide paths:
  about `93 ms` at `1k`, `874 ms` at `10k`, `4917 ms` at `50k`

What these results mean:

- the current main hotspots are table-wide fetch patterns, not relationship fan-out
- parent-scoped sync and parent-scoped export are paying for global child-table size rather than scoped-slice size
- single-item sync is too sensitive to total table size for a path that should represent incremental work
- relationship helpers are paying almost entirely for fetching the full related table

What these results do not yet prove:

- stable median and tail behavior across repeated runs
- mixed-workload behavior under more realistic app sessions
- whether a third party should treat the library as production-ready at higher dataset tiers

## Milestone 2 early findings

Reduced verification run completed for `sqlite + 1k` with repeated samples:

`SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_STORES=sqlite SWIFTSYNC_BENCHMARK_TIERS=1000 swift test --filter FetchStrategyBenchmarkTests`

What changed in the harness:

- isolated benchmark cases now emit `samples`, `medianMs`, and `maxMs`
- a new `mixed-session-workload` case exercises:
  - one incremental user sync
  - one parent-scoped task sync for the target project slice
  - one relationship-heavy work-item sync
  - one scoped export

Early signal from the repeated `1k` SQLite run:

- median and max were close for the isolated cases, which suggests the harness is stable enough for larger repeated runs
- the mixed workload landed at about `130 ms` median and `135 ms` max at `1k`, which is already more representative than quoting isolated-path timings alone

What still remains for Milestone 2:

- repeated SQLite runs at `10k` and `50k`
- deciding whether the mixed workload is representative enough or still needs a richer model graph

Expanded repeated SQLite run completed for `10k` and `50k` tiers with:

`SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_STORES=sqlite SWIFTSYNC_BENCHMARK_TIERS=10000,50000 swift test --filter FetchStrategyBenchmarkTests`

Additional findings:

- median/max spread stayed relatively tight across the published cases, even at `50k`
- that suggests the current hotspot pattern is stable and structural, not just an artifact of one noisy run
- mixed workload scaled in line with the isolated table-wide hotspots:
  about `1151 ms` median at `10k`
  about `5759 ms` median at `50k`
- isolated-path medians remained consistent with Milestone 1:
  - global batch sync: about `788 ms` at `10k`, `4178 ms` at `50k`
  - single-item sync: about `141 ms` at `10k`, `699 ms` at `50k`
  - parent-scoped batch sync: about `223 ms` at `10k`, `1070 ms` at `50k`
  - parent-scoped export: about `211 ms` at `10k`, `1023 ms` at `50k`
  - to-one FK resolution: about `170 ms` at `10k`, `906 ms` at `50k`

Milestone 2 interpretation so far:

- repeated samples improved confidence in the measurements
- the mixed workload confirms that the same table-wide fetch costs dominate when several operations are combined
- the benchmark evidence is now stronger than a pure microbenchmark suite, but it is still based on a relatively simple model graph

Remaining Milestone 2 question:

- whether we need one richer, less synthetic graph benchmark before treating the results as strong enough for third-party guidance

## Candidate focus areas

- Batch sync of a model with a large existing table.
- Parent-scoped sync where the global child table is much larger than the parent slice being updated.
- To-one and to-many relationship resolution when related tables are large.
- Export behavior when full-table reads are used for deterministic ordering.

## References

- `SwiftSync/Sources/SwiftSync/API.swift`
- `SwiftSync/Sources/SwiftSync/Core.swift`
- `SwiftSync/Sources/SwiftSync/SyncContainer.swift`
- `README.md`
- `ARCHITECTURE.md`
