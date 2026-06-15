# World-Class Roadmap

Goal: take SwiftSync from "very good SwiftData library" to world-class. This file is
the source of truth for that effort. Each open item is sized to be a single worktree
branch. Work through them systematically; mark complete by deleting the line (per
`docs/planning` cleanup rules) once merged.

## Baseline (2026-06-14)

- Root `swift test`: 149 tests pass, 9 benchmark skips. DemoCore: 21. DemoBackend: 21.
- Builds emit warnings (generated-macro warnings in root; Swift 6 sendability warnings
  in DemoCore). Not warning-clean.
- swift-tools `6.2`, language mode `.v6`. Platforms iOS 17 / macOS 14.
- CI (`ci.yml`): swift-format check + `swift test` on SwiftSync/DemoBackend/DemoCore.
  No warnings gate, no docs gate, no perf gate.

## Reference targets

- `code/3lvis/ios/Networking` — the version/platform north star: swift-tools `6.2`,
  `swiftLanguageModes: [.v6]`, platforms `iOS(.v18), macOS(.v15), tvOS(.v18), watchOS(.v11)`.
  SwiftSync matches on tools + language mode; the gap is platforms.

## Resolved decisions

- Platforms: **iOS 18 + macOS 15 only** (no tvOS/watchOS). Matches Networking's Swift
  version + iOS 18 floor; covers all tested surface.
- `migrating-from-sync.md`: **remove the two dangling links** (docs/README.md); defer any
  migration guide.
- Public extension points: the low-level helpers (`syncApplyTo*`, `exportSetValue`,
  `exportEncodeValue`, `ExportState`, `SyncRelationshipSchemaDescriptor`,
  `SyncRelationshipOperations`) **stay public by contract** — the `@Syncable` expansion emits
  calls to them in the *consumer's* module, so demoting them breaks every consumer. The
  accidental publics were the load-planning/freshness internals, now demoted to `internal`.

## Open decisions (resolve before/while doing the items they block)

- [ ] Decide SwiftData-modern stance per feature (`#Unique`, `#Index`, history API,
      custom `DataStore`, `#Expression`): adopt, interop-and-document, or out-of-scope.

## Open items

### Phase 3 — DocC + publishable API documentation

- [ ] Add a DocC catalog to the SwiftSync target with a landing page and curated topics.
- [ ] Document every public symbol surviving the API-surface tightening (Phase 5).
- [ ] Add a CI job that builds DocC (and optionally publishes to GitHub Pages).

### Phase 5 — Tighten the public API surface

- [ ] Document the intended public surface and the macro-support extension points (the
      helpers that must stay public) so they aren't mistakenly demoted later.

### Phase 6 — CI gates for world-class hygiene

- [ ] Add a warnings gate now that all packages are warning-clean: turn on
      `-warnings-as-errors` (or Swift 6.2 warning controls) for the library targets and/or
      enforce zero warnings in CI, so regressions can't reintroduce them.
- [ ] Add a docs gate: DocC build success + doc link-check (depends on Phases 2–3).
- [ ] Un-skip a small, fast benchmark subset and add a thresholded perf-regression gate;
      `log()` anything intentionally excluded so coverage isn't silently truncated.

### Phase 7 — Define the production-sync story (design-first)

The gap: SwiftSync is inbound-only (server → local, read-reactive); production sync adds the
outbound/offline side (local edits flow back). Design-first and substantial — deferred here from
Phase 4. Full design in [`production-sync-design.md`](production-sync-design.md): offline queue in
the DB, last-writer-wins, a visible/actionable failures table, offline-safe migrations, CloudKit out,
break-freely versioning; observability TBD.

Decided: **identity + change detection** use a `localId` + `remoteId` + `updatedAt` model — detection
is a query over the store (no save-interception; a `didSave`-interception spike was explored and
discarded as unnecessary), and conflicts resolve by latest `updatedAt`. The History API is an optional
later optimisation (efficient deltas / delete tombstones), not the foundation.

- [ ] Study prior art (the old `Sync`, WatermelonDB, PouchDB–CouchDB replication, Realm sync), then
      design the public outbound seam — syncable-model contract, pending queue, push hook, failures
      table — and build it with its first real use.
- [ ] Break each accepted area into its own implementation PR.
