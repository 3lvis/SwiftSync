# World-Class Roadmap

Goal: take SwiftSync from "very good SwiftData library" to world-class. This file is
the source of truth for that effort. Each open item is sized to be a single worktree
branch. Work through them systematically; mark complete by deleting the line (per
`docs/planning` cleanup rules) once merged.

Companion: [`api-surface-review.md`](api-surface-review.md) — a prioritized pass at keeping the public
API minimal (macros + convention over configuration), worked one item at a time.

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
- [ ] Generalize the inbound last-writer-wins read. The pull's per-row LWW (which stops a refresh from
      clobbering an un-pushed local edit) reads the incoming timestamp from the payload under the
      conventional `updatedAt` key. An offline model whose timestamp uses a `@RemoteKey` rename silently
      skips LWW (degrades to plain apply). Generalizing needs macro support to surface the model's
      timestamp key — add it only when a real consumer hits the rename case; don't add public API for it.

### Phase 8 — Failure handling (one coherent concern)

How SwiftSync **represents, reports, and surfaces** failure is a single design, not three tasks.
(Splitting it into taxonomy / observability / retry produced speculative pieces — `isRetryable` and a
library-carried error `code` with no real consumer.) Prior art is unanimous (PowerSync, WatermelonDB,
CloudKit/`NSPersistentCloudKitContainer`): **errors bubble up; the library persists no per-row failure
state; failed rows stay pending and retry; surfacing is an event stream; the inbox is an app concern.**

- [ ] **Represent + report (pure-bubble).** One `SyncError` currency for everything SwiftSync throws
      (`.invalidPayload` / `.cancelled` / `.schemaValidation` / `.containerInitialization`). For per-row
      *partial* push rejections, `push()` returns the outcomes (`failures: [{localID, operation, error}]`)
      and marks succeeded rows synced / leaves failed rows pending — it persists **nothing** on models
      (no `syncFailureReason`/`syncFailureCode` on `SyncOfflineModel`). The consumer owns any inbox
      persistence and reads the backend's own error in its `upload` closure. *Demo:* the engine annotates
      its own `Task` field from `summary.failures` and clears it on a later successful push.

- [ ] **Surface (observability).** A multi-consumer `events()` `AsyncStream` emitting per-sync outcomes
      (started/completed, applied/stale/rejected, counts, duration) — the prior-art surfacing channel
      (NSPCC's `eventChangedNotification`). The demo's failures view and "sync activity" build on it.
      Same concern as the bubble above; lands with or right after it. (↔ Networking roadmap item 3.)

**Out of SwiftSync — resilience.** Retry/backoff/`Retry-After`/auth-refresh are the *networking layer's*
job (the `code/3lvis/ios/Networking` interceptors, wired into the consumer's `upload` closure), by the
same "a sync library doesn't own the network" principle that keeps it from categorizing errors. Not a
SwiftSync feature.

### Phase 9 — Still open (genuinely separate)

- [ ] **7a → Sync-protocol prior-art scan** — largely done (PowerSync / WatermelonDB / CouchDB-PouchDB /
      CloudKit reviewed for the failure model); finish for the pull/cursor contract if hardened further.
- [ ] **7b → Offline-safe queue migrations + versioning** — deferred until there are shipped consumers
      with persisted queues to protect (the format can still break freely).

Each item is its own PR (some a short series). Core stays dependency-free; any concrete transport/bridge
is a separate SPM product (↔ Networking items 5–6).
