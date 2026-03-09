# Fetch Strategy Under Load

## Goal

Define the next high-leverage optimization step for the remaining fetch-strategy bottlenecks, using the benchmark findings already captured in `docs/project/fetch-strategy-under-load.md`.

## Priority framing

From the remaining work, the optimization options split into three groups.

### High-value, must-try

- Parent-scoped authoritative sync around scope-level diffing instead of full-table reconciliation.
  This is the strongest candidate. The realistic benchmark is project-scoped, and parent-scoped paths still scale with total child-table size instead of scope size. If one thing can move the headline number materially, it is this.
  Feasibility is promising but not fully proven, so this should start as a short experiment rather than a full commitment.

- Sync-pass identity index for target model rows, not just related rows.
  This is also worth trying. The same optimization class already produced a large win for relationship rows. Applying it to target rows could cut single-item sync and batch matching costs without adding public API surface.
  Feasibility is high and does not need a separate spike before implementation.

- Delete planning without full row materialization.
  High upside, but a bit riskier. If authoritative sync can decide insert/update/delete from compact identity sets first, global sync could drop a lot.
  Feasibility is high enough to try directly, but this is probably the third thing to try, not the first.

### Worth trying, but secondary

- Parent-scoped export narrowing by scope-first ordering instead of fetch-all-then-filter.
  Probably useful, but not the biggest product win unless export is on a hot path for users. Good cleanup after parent-scoped sync, not the main bet.
  Feasibility is reasonable, but it should follow the higher-impact sync-path work.

### Low-confidence / probably not worth trying early

- Revisit parent-scoped strategy at the API level.
  This should not be the starting point. API changes are expensive, and there are still internal implementation paths with bigger expected upside.
  This only becomes worth discussing if the internal options fail.

## Priority order

1. Start with a short experiment for parent-scoped authoritative sync around scope-level diffing.
2. If that path looks brittle or low-yield, move next to a sync-pass identity index for target model rows.
3. Try delete planning that operates on compact identity sets before full row materialization.
4. Follow with parent-scoped export narrowing if the main sync-path work still leaves obvious scope-related waste.
5. Only consider API-level parent-scoped strategy changes if the internal implementation paths fail to produce large enough gains.

## Open items

- [ ] Start with a short experiment for parent-scoped authoritative sync to confirm whether scope-level diffing is cleanly achievable in SwiftData.
- [ ] If the parent-scoped experiment looks brittle or low-yield, move next to a sync-pass identity index for target model rows.
- [ ] Try delete planning that operates on compact identity sets before full row materialization if the first chosen path does not move the headline scenario enough.
- [ ] Choose the next optimization target for Milestone 3 from the documented alternatives.
- [ ] Design the implementation shape for the chosen path before touching library code.
- [ ] Re-run the headline scenario and the supporting isolated benchmarks after the next optimization pass.
- [ ] Turn the post-optimization results into either a supported operating-envelope statement or explicit documented limits.
