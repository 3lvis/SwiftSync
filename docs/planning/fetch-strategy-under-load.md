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

## Open items

- [ ] Add benchmarks for the current full-table fetch paths in sync, relationship resolution, parent-scoped sync, and export.
- [ ] Define the dataset sizes and payload shapes the benchmarks must cover.
- [ ] Identify which measured paths can be improved without changing the public contract.
- [ ] Replace the worst full-table fetch paths with narrower fetches where SwiftData supports it cleanly.
- [ ] Define explicit caller options or documented limits for the paths that cannot be optimized enough.
- [ ] Update library docs to state the supported operating envelope and remaining scale-sensitive paths.

## Solution shape

- Benchmark first so optimization work is driven by measured cost instead of assumption.
- Optimize the paths that can be narrowed without making the API or implementation brittle.
- Expose clear limits or alternative usage guidance for the paths that must remain scale-sensitive.

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
