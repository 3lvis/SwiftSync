# State Capsule

## Plan

- [x] Rewrite `docs/planning/fetch-strategy-under-load.md` so it starts with one concrete Milestone 3 experiment instead of a generic option list.
- [x] Align the planning doc's open items with the docs/planning format and the retained benchmark findings.
- [x] Review the rewritten planning doc for consistency with `docs/project/fetch-strategy-under-load.md`.
- [x] Trace the current parent-scoped authoritative sync path and identify where it expands from scope-local work into full-table reconciliation.
- [x] Record the scoped-sync findings in the planning doc as the implementation starting point.
- [x] Decide whether the first Milestone 3 step should stay docs-only or move into code.
- [x] Add a regression test covering sequential sync coherence in the same `ModelContext`.
- [x] Add a context-local target-row cache for repeated syncs in the same `ModelContext`.
- [x] Re-run the headline scenario at reduced tiers and decide whether the target-row cache is worth pursuing at `10k`.
- [x] Remove the low-yield target-row cache after measuring it.
- [x] Shift the Milestone 3 plan to delete planning without full row materialization.
- [x] Trace the authoritative batch sync delete path and identify the minimum data it needs before deletion.
- [x] Add focused coverage for the sequential-sync coherence risk while exploring delete-planning changes.
- [x] Implement and measure a minimal-properties fetch variant for delete planning.
- [x] Remove the minimal-properties fetch variant after it regressed the headline benchmark.
- [~] Shift the Milestone 3 plan to a different delete-planning experiment without full row materialization.

## Last known state

Scoped parent-fetch optimization is compiler-blocked because SwiftData rejects `row[keyPath: ...]` inside `#Predicate`. The context-local target-row cache was measured and removed as low-yield, and the minimal-properties fetch variant for delete planning was also rejected after regressing the headline benchmark to about `719 ms` at `sqlite + 1k` and `7379 ms` at `sqlite + 10k`. Focused parent/sync tests are green on the cleaned-up code.

## Decisions (don't revisit)

- This task starts in docs only; no library behavior change is planned in this pass.
- The planning doc should choose a concrete starting experiment, not preserve every previously considered option at equal weight.
- The first implementation-oriented step is to map the existing scoped sync path precisely before attempting any optimization.
- Any scope-first implementation must account for the mismatch between `ParentScopedModel.parentRelationship` and the generic sync APIs that accept arbitrary parent relationship key paths.
- The scope-first parent-fetch experiment is blocked for now because SwiftData predicates do not support `subscript(keyPath:)` in the required generic form.
- The target-row cache is not worth keeping as a retained optimization because the headline `10k` gain is only about `4.4%`.
- The delete-planning pass should stay behavior-preserving and target only the data needed to decide deletions before touching broader sync structure.
- The `propertiesToFetch` fetch-shaping variant is not worth revisiting for delete planning because it regressed the headline benchmark at both `1k` and `10k`.

## Files touched

- .agents/state.md
- docs/planning/fetch-strategy-under-load.md
- SwiftSync/Sources/SwiftSync/API.swift
- SwiftSync/Tests/SwiftSyncTests/SyncTests.swift
