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

### Phase 5 — Tighten the public API surface (deferred to first release / tag time)

- [ ] **Not now — do this when we cut the first tag.** Document the intended public surface and the
      macro-support extension points (the helpers that must stay public) so they aren't mistakenly
      demoted later. Lands alongside the release-time API-breakage gate (Phase 6); there's nothing to
      protect until there's a tag to diff against.

### Phase 6 — CI gates for world-class hygiene

- [ ] Add a warnings gate now that all packages are warning-clean: turn on
      `-warnings-as-errors` (or Swift 6.2 warning controls) for the library targets and/or
      enforce zero warnings in CI, so regressions can't reintroduce them.
- [ ] Un-skip a small, fast benchmark subset and add a thresholded perf-regression gate;
      `log()` anything intentionally excluded so coverage isn't silently truncated.
- [ ] **API-breakage gate (do at first release / tag time).** Once there's a published tag to diff
      against, add `swift package diagnose-api-breaking-changes <last-tag>` as a CI gate on the
      **SwiftSync** library: it serializes the public API surface (via `swift-api-digester`) and fails the
      PR on any source-breaking change (removed/renamed public symbol, changed signature, dropped
      conformance). Intentional breaks go in `--breakage-allowlist-path`. This is the Apple-style,
      high-signal check for a library — pairs with Phase 5 and `api-surface-review.md`, and is far more
      on-brand than a coverage %. Canonical implementation: the reusable `swiftlang/github-workflows`
      `soundness.yml` (`api_breakage_check`). It only becomes meaningful with a baseline tag, so it's
      gated on the first release, not now.
- [x] Self-hosted core-coverage evaluation + regression gate for `SwiftSync/Sources` (per-file
      evaluation, patch gate on new core lines, no-decrease gate) — shipped in #636. Doc-only PRs skip the
      heavy CI via `paths-ignore` — shipped in #637.

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

- [x] **Layered sync architecture documented + enforced** — Views → per-screen state machines →
      DemoSyncEngine (networking + orchestration) → SwiftSync (pure storage). SwiftSync stays storage-only
      (`withPendingChanges` is the push primitive); the engine owns drain/reconnect/coalescing. Canonical:
      [`../project/architecture.md`](../project/architecture.md). (The earlier "fold the driver into the
      library" idea — [`sync-engine-fold.md`](sync-engine-fold.md) — was explored and reverted: orchestration
      is app policy, not storage.)
- [ ] Formal prior-art scan of the sync *protocol* (PowerSync, CouchDB/PouchDB replication,
      WatermelonDB, Realm/Firestore) before hardening the push/pull contract further — pick
      deliberately for our constraints (this gates the Phase 8 middleware seam).
- [ ] Offline-safe migrations + break-freely versioning of the pending-change/queue format.

### Phase 8 — Failure handling (one coherent concern)

How SwiftSync **represents, reports, and surfaces** failure is a single design, not three tasks.
(Splitting it into taxonomy / observability / retry produced speculative pieces — `isRetryable` and a
library-carried error `code` with no real consumer.) Prior art is unanimous (PowerSync, WatermelonDB,
CloudKit/`NSPersistentCloudKitContainer`): **errors bubble up; the library persists no per-row failure
state; failed rows stay pending and retry; surfacing is an event stream; the inbox is an app concern.**

- [ ] **Represent + report (pure-bubble).** One `SyncError` currency for everything SwiftSync throws
      (`.invalidPayload` / `.cancelled` / `.schemaValidation` / `.containerInitialization`). For per-row
      *partial* push rejections, `withPendingChanges()` returns the rejected rows (`[SyncPushFailure]` of
      `{id, error}`) and marks succeeded rows synced / leaves failed rows pending — it persists
      **nothing** on models (no `syncFailureReason`/`syncFailureCode` on `SyncOfflineModel`). The consumer
      owns any inbox persistence and reads the backend's own error in its `process` closure. *Demo:* the engine annotates
      its own `Task` field from the returned failures and clears it on a later successful push.

- [ ] **Surface (observability).** A multi-consumer `events()` `AsyncStream` emitting per-sync outcomes
      (started/completed, applied/stale/rejected, counts, duration) — the prior-art surfacing channel
      (NSPCC's `eventChangedNotification`). The demo's failures view and "sync activity" build on it.
      Same concern as the bubble above; lands with or right after it. (↔ Networking roadmap item 3.)

**Out of SwiftSync — resilience.** Retry/backoff/`Retry-After`/auth-refresh are the *networking layer's*
job (the `code/3lvis/ios/Networking` interceptors, wired into the consumer's `process` closure), by the
same "a sync library doesn't own the network" principle that keeps it from categorizing errors. Not a
SwiftSync feature.

### Phase 9 — Still open (genuinely separate)

- [ ] **7a → Sync-protocol prior-art scan** — largely done (PowerSync / WatermelonDB / CouchDB-PouchDB /
      CloudKit reviewed for the failure model); finish for the pull/cursor contract if hardened further.
- [ ] **7b → Offline-safe queue migrations + versioning** — deferred until there are shipped consumers
      with persisted queues to protect (the format can still break freely).

Each item is its own PR (some a short series). Core stays dependency-free; any concrete transport/bridge
is a separate SPM product (↔ Networking items 5–6).

### Demo app — follow-ups

- [x] **Consolidate the online people-edit save into one round-trip.** Done: `updateTask`/`createTask`
      now honor `reviewer_ids`/`watcher_ids` in the task body (the `.save` handler in `ScreenMachines.swift`
      adds the `@NotExport` people to the body and drops the separate `replaceTaskReviewers`/
      `replaceTaskWatchers` calls), so a people edit is a single server round-trip. The offline local
      apply (`applyLocalTask`) sets the `@NotExport` reviewers/watchers relationships from the body, since
      `apply()` won't — so an offline people edit shows before any round-trip. UI save-dismiss waits were
      unified on one `saveDismissTimeout` (3s — sized for a one-round-trip save plus CI jitter, not a
      bloated ceiling: `waitForNonExistence` returns on dismiss, so a real failure still fails fast).

### Offline / two-id identity model — follow-ups (PR #632)

Grouped by layer. The identity model: the backend keeps its own internal `INTEGER PRIMARY KEY` (joins/FKs,
**never exposed**); every row carries a `public_id` UUID that is the sole external identity (exposed as
`"id"`, addressed by REST + `/sync/upload`). Client-originated rows adopt the client's id as `public_id`;
server-origin rows get a server-minted UUID. The client deals only in `public_id`.

**Layer: SwiftSync library (the product)**

- [ ] **Local history growth / trimming.** Offline detection reads SwiftData history authored locally
      since a per-type "last pushed" token (`PushHistoryTokenRecord`). On a successful push we advance the
      token and trim **inbound** (pull-authored) history up to it (`trimInboundHistory`), but leave
      already-pushed **local-authored** history in place (inbound-only trim avoids a cross-type token
      hazard). So history accumulates with every local edit over the app's lifetime. *Fix:* a safe trim
      policy for already-pushed local history (e.g. below the *minimum* token across all offline types),
      and verify what SwiftData's DefaultStore already TTL-trims. *The one genuine product follow-up; slow
      growth, not urgent.* (`Push.swift` / `PushHistoryTokenStore.swift`.)
- [ ] **Macro can't auto-add `.preserveValueOnDeletion`.** Offline opt-in is marking the identity
      `@Attribute(.unique, .preserveValueOnDeletion)`; a Swift peer/extension macro can't attach an
      attribute to a stored property, so it's a documented requirement enforced at runtime
      (`requireOfflineCapable` throws). *Known limitation, low priority* — revisit only if a macro role that
      can inject it appears. (`MacrosImplementation` / `OfflineDetection.swift`.)

**Layer: demo backend (`DemoServerSimulator`) — real-server fidelity, not the library**

- [ ] **Item-update churn → reconcile items by `public_id`.** A task's items travel as a full array on each
      update; the backend does *delete-all-items → re-insert the array*, so every item row + internal int
      id is recreated on every edit (even unchanged ones), violating the "stable, immutable identity" rule.
      *Fix:* upsert each incoming item by its `public_id` (update if present, insert if new), delete the
      ones whose `public_id` isn't in the incoming set. *Most real of these — a correctness/consistency
      gap, invisible today only because nothing downstream depends on item-id stability yet.*
- [ ] **Atomic upsert.** `/sync/upload` does `SELECT id WHERE public_id` *then* insert-or-update; two
      concurrent pushes of the same `public_id` could both see "not found" and both insert → unique
      violation or duplicate. *Fix:* `INSERT … ON CONFLICT(public_id) DO UPDATE` (or a txn that catches the
      unique violation as the update branch). Invisible in the demo (single-threaded SQLite); a real
      concurrent server needs it.
- [ ] **Authorization / id-squatting (production only).** The client supplies the `public_id`, which is
      also the shareable URL id, so anyone who knows it can address that row; `UNIQUE` won't stop an
      upsert/delete of *someone else's* row. A real server must authorize writes by row ownership (the
      security boundary is authz, not id secrecy). Out of scope for the demo (no auth/principals); flagged
      because client-minted ids are what surface it.

**Layer: docs**

- [ ] **Capture the final identity model** in `offline-history-design.md`: internal int PK (never exposed),
      `public_id` as the sole external identity, the dual-minting + adopt rule, and the rationale
      (idempotency on lost-response retry, shareable URL id, reach over existing backends). The doc still
      describes the superseded #630 collapsed-id / `SyncOffline`-marker model — refresh it.
- [ ] **Rewrite `upload-endpoint-contract.md`** to the collapsed-id model. It still documents the original
      two-id (`localId` + server-minted `remoteId`) wire protocol; the shipped reality is one id (client id
      adopted as `public_id`, no `remoteId`) and the demo's wire key is now `"id"`. Currently carries a
      staleness banner pointing at `offline-history-design.md`.
