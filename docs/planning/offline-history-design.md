# Offline push via SwiftData History — design

Status: **complete** on branch `spike/offline-zero-fields`. SwiftSync unit suite (168 tests) +
DemoCore suite (36 tests, incl. the 16-case offline integration suite) green; Demo app builds.
Supersedes API-surface-review item #2 ("macro-generate `SyncOfflineModel`") — there is no
`SyncOfflineModel` to generate; offline rides SwiftData History instead.

## The mental model

Offline push needs three facts per row: **has it been pushed**, **was it edited since last push**, and
**was it deleted** (so we can push the deletion). Every prior approach stores those facts *somewhere* —
WatermelonDB puts `_status`/`_changed` columns on the row; PowerSync/Replicache keep an upload queue.

A `@Syncable @Model` can't carry those as macro-added fields (an attached macro can't add
SwiftData-persisted stored properties — `@Model` only persists what it sees in the original
declaration). The first spike answer was a parallel `SyncMetadata` table kept in sync by a `didSave`
observer; benchmarks showed that taxes every pull **2.3×–69×** because it writes a bookkeeping row per
pulled row.

The real answer: **don't store those facts — derive them from SwiftData's own change history.**
SwiftData History (iOS 18+) already records every insert/update/delete as `DefaultHistoryTransaction`s,
each tagged with an **author** and ordered by a **token**. So:

- **"Edited since last push"** = transactions whose `token` is greater than the saved cursor.
- **"Local vs pulled"** = author. SwiftSync stamps inbound (pull) writes with `inboundAuthor`; local
  edits leave the default (nil) author. `pendingChanges` keeps only non-inbound transactions, so a
  pulled row is never mistaken for a local insert and pushed back.
- **"Deleted"** = a delete transaction. Marking the identity `@Attribute(.preserveValueOnDeletion)`
  keeps the id readable in the tombstone, so a plain `context.delete(row)` is enough to recover the
  deleted `id` at push time.

**Opt-in = `.preserveValueOnDeletion` on the identity.** That attribute is genuinely *required* for
offline (to recover deleted ids) and is a harmless no-op otherwise, so its presence is the honest
signal: when set, the model gets offline pull semantics (honor pending local edits, preserve
never-pushed inserts) and is pushable; when absent, the model keeps plain "server is authoritative"
pull. No separate marker protocol. This opt-in is *necessary*, not cosmetic — the core diffing tests
proved that applying offline last-writer-wins to every model breaks the "a plain pull always updates
existing rows" contract.

**The cursor is internal.** SwiftSync stores a `DefaultHistoryToken` per model type in a tiny
`SyncCursorRecord` model (O(model types) rows, written once per push — not per data row, no pull-path
cost), auto-registered in the container. The consumer never sees or manages a cursor. Push reads
history since the stored cursor, uploads, and — only if everything was acknowledged — advances the
cursor and trims the now-redundant inbound history.

### Why it works / why it's cheap

- **Pulls write nothing extra.** Offline tracking is a *read* of history at push time, not a write on
  the pull path. Measured: 100k pull ≈ 12s (same as a non-offline full sync), vs 2.3×–69× for the table.
- **Push detection is proportional to local change, not table size.** "Nothing pending" returns in
  ~1ms (history query only; the live-row fetch is skipped when there are no local transactions).
- **Near-zero consumer surface.** One attribute option (`.preserveValueOnDeletion`) on the identity —
  no `syncRemoteID`/tombstone/`updatedAt` sync fields, no `SwiftSync.delete` ceremony. The consumer
  uses plain SwiftData inserts/edits/`context.delete`.
- **Collapsed id model** (decided with the user): the client `id` *is* the identity the backend
  adopts; there is no separate server-assigned id to map home. Push is an idempotent **upsert**, so
  insert vs update need not be distinguished on the wire — and confirmations need not be echoed: the
  `process` closure returns only `[SyncPendingChangesFailure]`, and the library confirms everything else by complement.

## What changed in code

- `Push.swift`: `SyncCursor` (= `DefaultHistoryToken`), `SwiftSync.inboundAuthor`, history-based
  `pendingChanges(for:in:)` / `withPendingChanges(for:in:process:)` (cursor internal, no
  `changedSince`/return cursor), `locallyDirtyPersistentIDs`, `trimInboundHistory`, `localTransactions`,
  `latestToken`. The insert-then-delete-before-push case is dropped (server never saw it). Both the
  `process` closure and `withPendingChanges` return `[SyncPendingChangesFailure]` (confirmations derived by
  complement; no summary/cursor for the caller to handle).
- `SyncCursorStore.swift`: internal `SyncCursorRecord` (per-type token) + read/write helpers.
- `OfflineDetection.swift`: `identityPreservesValueOnDeletion` (the opt-in check) + `requireOfflineCapable`
  (push/pending throw a clear diagnostic if the identity isn't `.preserveValueOnDeletion`).
- `API.swift`: pull computes the dirty-set (`offlineDirtyPersistentIDs`, gated on the opt-in) and uses it
  in `isUnsyncedLocalInsert` (delete-missing preservation) and `applyHonoringLocalEdit` (LWW).
- `SyncContainer.swift`: registers `SyncCursorRecord`; bulk-sync contexts stamp `inboundAuthor`;
  single-item `sync(item:)` stamps the author save-scoped (set + restore) so later local writes aren't
  mislabeled. The `SyncMetadata` table, its `didSave` observer, and the gating flag are gone.
- Demo `Task`: zero offline fields (kept demo-owned `@NotExport syncFailureReason`); id
  `.preserveValueOnDeletion`. `DemoSyncEngine` does local writes as plain SwiftData (via the macro's
  `make`/`apply`, local-authored), offline delete is a hard delete, push/pending use the new API.
- Tests: `OfflineHistoryTests` (mechanism + 100k benchmark), `OfflinePushTests` (push partitioning,
  acknowledgement, failures), `InboundPrunePreservesPendingTests` (the #625 guarantees, rebuilt).

All open items from the spike (LWW + insert preservation, history trimming, single-item author tagging,
the preserve-on-deletion requirement, parked-test migration, demo migration) are resolved.

## Notes / non-obvious decisions

- **`.preserveValueOnDeletion` can't be macro-added.** A peer/extension macro can't attach an attribute
  to a stored property, and forcing it on every `@Syncable` model would wrongly burden pull-only types.
  So it's a documented, validated requirement (push/pending throw if it's missing), not codegen.
- **Offline requires a persistent store.** History works on in-memory stores in current SwiftData (the
  test suite confirms), but offline-first fundamentally implies persistence; don't rely on ephemeral.
- **Local writes must not go through `sync(item:)`.** That path is inbound (server→local) and is
  author-tagged; a local create/edit done through it would be mislabeled and never pushed. The demo
  applies local edits with the macro's `make`/`apply` on `mainContext` instead.
