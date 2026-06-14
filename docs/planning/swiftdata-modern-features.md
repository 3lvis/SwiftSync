# SwiftData-Modern Features — Evaluation Plan

Roadmap Phase 4. We evaluate each modern SwiftData feature (WWDC24+) **one at a time, hands-on**:

1. **Implement / adopt** it into SwiftSync (or the demo).
2. **Measure before/after** — a perf benchmark for performance features (the `FetchStrategyBenchmarkTests` harness), or a before/after **developer-experience** comparison for ergonomics features.
3. **Decide** — keep it only if it genuinely improves things and *feels natural*; otherwise record why not.
4. **Document** the outcome here.

One feature = one workstream = one PR. Record the baseline on the same benchmark before changing anything (per AGENTS.md).

## Status

| Feature | Status | Outcome |
|---|---|---|
| `#Index` | ✅ evaluated | **Not adopted in the library** (see below) |
| `#Unique` | ⬜ todo | — |
| `#Expression` / richer predicates | ⬜ todo | — |
| History API | ⬜ todo | — |
| Custom `DataStore` | ⬜ todo | — |

## Findings

### `#Index` — evaluated, not adopted (library level)

Measured parent-scoped sync on a SQLite store, 20 000 total rows, 100 in-scope, 3 samples each (`FetchStrategyBenchmarkTests`):

| Scenario | Baseline (no index) | `#Index([\.project])` |
|---|---|---|
| parent-scoped single-item sync | 28.2 ms | 27.4 ms |
| parent-scoped batch sync | 40.1 ms | 40.2 ms |

Both within noise. Reason: SwiftSync identifies rows by `syncIdentity`, which is conventionally `@Attribute(.unique)` — and SwiftData already indexes unique attributes. That index dominates the fetch; the residual cost is row materialization/save, which an extra index can't help (it only adds write-time maintenance).

**Stance:** `#Index` is **consumer-optional** — apps can add it to their *own* non-unique query/sort columns if profiling shows a need. SwiftSync does not auto-generate it in `@Syncable` (no read benefit on its access patterns, and it would slow writes).

## Open items

- [ ] `#Unique`: try compound uniqueness on a model and compare DX vs the current `@Attribute(.unique)` + `syncIdentity` convention; does it simplify identity modeling or conflict with sync upserts?
- [ ] `#Expression` / richer predicates: use in a `@SyncQuery`/`SyncQueryPublisher` predicate; does it improve query ergonomics for consumers?
- [ ] History API: evaluate whether `HistoryDescriptor`/transaction history can replace or strengthen the `didSave` + `syncMarkChanged` dirty-tracking workaround, and feed change-export (links to the Phase 7 production-sync story).
- [ ] Custom `DataStore`: confirm SwiftSync works against a custom store; document the contract it relies on (fetch, save, relationship faulting, `didSave` notifications) and any caveats.
