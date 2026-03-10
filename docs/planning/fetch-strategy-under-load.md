# Fetch Strategy Under Load

## Goal

Start Milestone 3 with the highest-leverage retained optimization target from the benchmark findings in `docs/project/fetch-strategy-under-load.md`.

## Starting point

Begin with a parent-scoped authoritative sync experiment that diffs within the requested scope instead of reconciling against the full child table.

This is the best first bet because the retained benchmark story still shows the same structural problem in the scoped paths:

- parent-scoped batch sync with a fixed `100`-row scope still grows from about `29 ms` at `1k` to about `1099 ms` at `50k`
- parent-scoped export follows the same full-table growth pattern
- the realistic mixed project/task scenario is project-scoped, so wins here have the clearest path to improving the headline number

## What this experiment needs to prove

The experiment is worth keeping only if it demonstrates all of the following:

- the scoped authoritative path can fetch and diff only rows for the requested parent scope
- the implementation does not require public API expansion or model-authored fetch hooks
- the scoped path stays correct for inserts, updates, and deletions when the payload is authoritative within that scope
- the headline project/task scenario moves enough to justify carrying the extra implementation complexity

If any of those fail early, the next step should be a sync-pass identity index for target model rows.

## Current trace

The current parent-scoped path still expands into full-table work before it ever applies the parent scope.

- `SwiftSync.sync(item:parent:relationship:)` fetches `FetchDescriptor<Model>()` and then filters the full result in memory to `scopeRows`.
- `SwiftSync.sync(payload:parent:relationship:)` does the same full-table fetch, then filters to `scopeRows`, and in the `isGlobal` branch it builds the duplicate-detection index from the full table instead of the parent scope.
- Authoritative delete planning is scope-local only after that full-table fetch, because deletions iterate `scopeRows` produced from the in-memory filter.
- `resolveParent` also fetches all `Parent` rows and then finds the one matching `persistentModelID`.
- Parent-scoped export follows the same pattern: fetch all `Model` rows, then filter in memory by `parentRelationship`.

That means the first experiment does not need a broad search for hidden complexity. The current starting boundary is clear: replace the fetch-all-then-filter stages in scoped sync and scoped export with scope-first fetches or a SwiftData-compatible equivalent.

## Design constraint

The current optimization target is not purely mechanical.

- `ParentScopedModel` exposes a static `parentRelationship`, which could support a specialized internal scoped-fetch path.
- The existing parent-scoped sync APIs are more generic than that protocol surface, because they accept arbitrary `ReferenceWritableKeyPath<Model, Parent?>` values.
- Earlier work already established that generic SwiftData predicate construction around arbitrary key paths is not a reliable path in this codebase.

So the first code experiment should begin by deciding between two implementation shapes:

1. Special-case the internal fast path for models where the requested relationship is the model's declared `ParentScopedModel.parentRelationship`.
2. Treat the generic key-path API as the blocker and fall back to the next Milestone 3 optimization instead of forcing more API or model complexity.

That decision is now made for this branch: SwiftData rejects `row[keyPath: ...]` inside `#Predicate`, even in the specialized `ParentScopedModel` helper shape, so the scope-first parent fetch path is blocked without broader API or model changes.

## Current active path

Milestone 3 briefly moved to the fallback target-row optimization:

- keep a context-local cache of fetched target rows keyed by `ModelContext` and model type
- reuse those rows across sequential sync operations in the same context
- update the cache after creates and authoritative deletes so later syncs in the same context do not refetch the full table immediately

That experiment was measured and then removed because the headline gain was too small:

- demo-shaped scenario, `sqlite + 1k`: about `664 ms` median versus the documented `713 ms` baseline
- demo-shaped scenario, `sqlite + 10k`: about `6638 ms` median versus the documented `6943 ms` baseline

The `10k` gain is about `4.4%`, which is below the bar for carrying additional cache state and coherence risk, so this path should be treated as another rejected optimization.

## Fallback order

If the parent-scoped experiment is brittle or low-yield, continue in this order:

1. Build a sync-pass identity index for target model rows.
2. Separate delete planning from full row materialization.
3. Narrow parent-scoped export by scope-first ordering.
4. Revisit API-level parent-scoped strategy changes only if the internal paths fail.

## Open items

- [ ] Switch the active Milestone 3 plan to delete planning without full row materialization.
- [ ] Define the smallest delete-planning experiment that can avoid full row materialization while preserving authoritative semantics.
- [ ] Avoid the rejected `propertiesToFetch` fetch-shaping path for delete planning; it regressed the headline benchmark to about `719 ms` at `sqlite + 1k` and `7379 ms` at `sqlite + 10k`.
- [ ] Avoid the rejected identifier-first rehydration path for delete planning; it regressed the headline benchmark to about `736 ms` at `sqlite + 1k` and `7174 ms` at `sqlite + 10k`.
- [ ] Re-run the headline project/task scenario and at least one supporting isolated benchmark after the delete-planning experiment.
- [ ] Convert the post-optimization measurements into an updated operating-envelope statement or documented limits.
