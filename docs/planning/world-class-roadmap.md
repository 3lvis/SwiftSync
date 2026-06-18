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

### Phase 7 — Production-sync story (foundation shipped)

SwiftSync was inbound-only (server → local, read-reactive); production sync adds the outbound/offline
side (local edits flow back). The **foundation shipped in #622**: offline queue (pending changes are a
query over the store — no save-interception; the `didSave` spike was explored and discarded), two-id
upsert push contract (`localId` stable key + server-minted `remoteId`), last-writer-wins on
`updatedAt` (including tombstone revival), and a visible/actionable **failures inbox** (edit-to-retry /
discard), with auto-sync on reconnect. Full design in
[`production-sync-design.md`](production-sync-design.md); the History API stays an optional later
optimisation (efficient deltas), not the foundation.

Still open:

- [ ] Formal prior-art scan of the sync *protocol* (PowerSync, CouchDB/PouchDB replication,
      WatermelonDB, Realm/Firestore) before hardening the push/pull contract further — pick
      deliberately for our constraints (this gates the Phase 8 middleware seam).
- [ ] Offline-safe migrations + break-freely versioning of the pending-change/queue format.

### Phase 8 — Outbound sync → best-in-class (adapted from `code/3lvis/ios/Networking` roadmap, items 2–4)

Three hardening items on top of the Phase 7 foundation. Each is driven by the demo as the forcing
function — a user-facing capability → a backend contract → the app supports it → that pulls the
feature into SwiftSync. Build each seam with its first real use, never speculatively.

- [ ] **Typed failure taxonomy.** Replace `SyncPushFailure`'s bare `message: String` with a
      categorized failure (`validation` / `staleConflict` / `transport` / `serverRejected`),
      preserving the underlying cause, plus a conservative `isRetryable`. Lets the failures inbox
      distinguish "fix this field" from "transient, will retry," and feeds the retry policy below.
      *Demo:* the inbox renders a fixable validation error differently from a transient one.
      (↔ Networking roadmap item 2 — categorize by where it failed, keep the cause, derive `isRetryable`.)

- [ ] **Sync observability — event stream + built-in logging.** A multi-consumer `events()`
      `AsyncStream` emitting per-sync/per-operation outcomes (started/completed, applied/stale/rejected,
      counts, duration), plus scoped built-in logging (debug shows, release redacts). Makes conflicts and
      failures observable instead of guesswork (the conflict/tombstone bugs this cycle were caught by
      hand-instrumentation that this would make first-class).
      *Demo:* a "sync activity" view. (↔ Networking roadmap item 3 — one `events()` hook + lossless
      built-in logging with one redaction rule.)

- [ ] **Push middleware — retry + auth refresh.** Formalize auto-sync-on-reconnect into a retry policy
      (exponential backoff + full jitter + `Retry-After`), safe because the upsert is idempotent (keyed
      on `localId`); single-flight credential refresh for concurrent auth failures (the 401 stampede);
      the `upload` closure is the interceptor seam. Consumes the `isRetryable` from the failure taxonomy.
      *Demo:* a "flaky network" toggle → backed-off retries; an "expired token" → one refresh + replay.
      (↔ Networking roadmap items 4b/4c — async-`next` interceptor onion, single-flight `RefreshCoordinator`,
      idempotent-methods-only retry.)

**Priority (across the open Phase 7 + Phase 8 items), by leverage and dependency:**

1. **8.1 Typed failure taxonomy** — smallest, hard-unblocks 8.3 (retry consumes `isRetryable`), and
   immediately upgrades the shipped failures inbox. Best effort/leverage ratio.
2. **8.2 Sync observability** — independent and high-leverage; gives eyes for building the riskier
   middleware (this cycle's conflict/tombstone bugs were caught by hand-instrumentation).
3. **7a Sync-protocol prior-art scan** — cheap, gates 8.3's seam design; do it right before, not early.
4. **8.3 Push middleware (retry + auth refresh)** — the big one (a PR series); unblocked by 8.1 + 7a,
   observable via 8.2.
5. **7b Offline-safe queue migrations** — deferred: the queue format can still break freely (no shipped
   consumers with persisted data), so versioning earns its place only once there's data to protect.

Each item is its own PR (some a short series). Core stays dependency-free; any concrete transport/bridge
is a separate SPM product (↔ Networking items 5–6).
