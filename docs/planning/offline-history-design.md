# Offline push via SwiftData History — design

Status: **shipped**. This supersedes the earlier `SyncOfflineModel` and two-id designs. Offline state is
derived from SwiftData History; models carry no SwiftSync-specific queue fields.

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
`PushHistoryTokenRecord` model (O(model types) rows, written once per push — not per data row, no pull-path
cost), auto-registered in the container. The consumer never sees or manages a cursor. Push reads
history since the stored cursor, uploads, and — only if everything was acknowledged — advances the
cursor. Each successful inbound sync deletes its own author-tagged history after notifying observers;
ordinary app-authored history remains app-owned because other history consumers may still need it.

## Identity contract

The client and server share one external identity:

- Every client row has a stable string `id`; the client mints it for offline-created rows.
- The backend stores its own internal primary key for joins and foreign keys. That key never appears on
  the wire.
- The backend also stores a unique `public_id`, exposed as `id` in every API. A client-created row adopts
  the client's `id`; a server-created row receives a server-minted `public_id` before the client sees it.
- REST routes, pull payloads, and `/sync/upload` all address the same external `id`. There is no
  `localId`/`remoteId` pair and no client-side identity rewrite.

Adopting a client-minted id makes an upsert retry-safe after a lost response: the retry addresses the
same unique `public_id` and converges on the existing row. Keeping the backend's internal primary key
separate preserves conventional database joins without exposing implementation identity.

### Why it works / why it's cheap

- **Pulls write nothing extra.** Offline tracking is a *read* of history at push time, not a write on
  the pull path. Measured: 100k pull ≈ 12s (same as a non-offline full sync), vs 2.3×–69× for the table.
- **Push detection is proportional to local change, not table size.** "Nothing pending" returns in
  ~1ms (history query only; the live-row fetch is skipped when there are no local transactions).
- **Near-zero consumer surface.** One attribute option (`.preserveValueOnDeletion`) on the identity —
  no `syncRemoteID`/tombstone/`updatedAt` sync fields, no `SwiftSync.delete` ceremony. The consumer
  uses plain SwiftData inserts/edits/`context.delete`.
- **One external id.** The client `id` *is* the identity the backend
  adopts; there is no separate server-assigned id to map home. Push is an idempotent **upsert**, so
  insert vs update need not be distinguished on the wire — and confirmations need not be echoed: the
  `process` closure returns only `[SyncPendingChangesFailure]`, and the library confirms everything else by complement.

## Notes / non-obvious decisions

- **`.preserveValueOnDeletion` can't be macro-added.** A peer/extension macro can't attach an attribute
  to a stored property, and forcing it on every `@Syncable` model would wrongly burden pull-only types.
  So it's a documented, validated requirement (push/pending throw if it's missing), not codegen.
- **Offline requires a persistent store.** History works on in-memory stores in current SwiftData (the
  test suite confirms), but offline-first fundamentally implies persistence; don't rely on ephemeral.
- **Local writes must not go through `sync(item:)`.** That path is inbound (server→local) and is
  author-tagged; a local create/edit done through it would be mislabeled and never pushed. The demo
  applies local edits with the macro's `make`/`apply` on `mainContext` instead.
