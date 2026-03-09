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

The goal is to decide what the project wants to claim, not how to optimize it yet.

## Open items

- [ ] Inventory the sync paths that currently fetch complete model tables before filtering or indexing.
- [ ] Describe the data-shape variables that matter for runtime cost: total row count, payload size, parent-scope width, and relationship fan-out.
- [ ] Define the dataset sizes that represent “small,” “moderate,” and “large” for SwiftSync evaluation.
- [ ] Decide whether SwiftSync intends to support large local stores or explicitly target modest dataset sizes.
- [ ] Define what evidence is required to justify that claim: benchmarks, profiling traces, or documentation limits.
- [ ] Write acceptance criteria for this planning item in terms of documented expectations and measurable validation goals, without choosing implementation changes yet.

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
