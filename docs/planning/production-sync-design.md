# Production Sync — Design (Phase 7)

Framing for the gap from today's **inbound sync-assist** (server → local SwiftData, read-reactive)
to **production sync** (local edits flow back out, offline-first). Design-first: this records the
decisions made so far and the open forks; implementation follows in dedicated PRs once the open
forks are resolved.

**Guiding principle:** the consumer should have to think as little as possible. Be opinionated —
dictate the contract rather than support every backend shape. SwiftSync provides the local queue,
change detection, and failure surface; the app owns the network calls.

## Decisions

- **Offline edits live in the database.** Pending local mutations persist in the local SwiftData
  store (a queue), so they survive app restarts. SwiftSync owns the queue; the **client app uploads
  them to the server** (SwiftSync detects/export changes and exposes the queue — it does not own the
  network transport).

- **Conflict resolution: last-writer-wins.** No per-field merge in the core.

- **Failure handling: a visible, actionable failures table.** Failed uploads are stored (not
  silently retried forever); the app/user can act per item — **discard, edit, retry** — like Google
  Photos' offline-sync failure list. SwiftSync surfaces the table and the actions; the app decides
  policy.

- **Observability: TBD — maybe not needed.** SwiftSync has *no* `print`/logging in its library
  source today (the earlier "remove print" note was a mix-up with the Networking repo). Whether to
  add structured sync-lifecycle hooks is undecided — revisit once outbound sync exists and we can see
  what's actually worth surfacing.

- **Schema migration: optimistic, with offline-safe nuclear option.** Prefer lightweight migrations;
  when a destructive ("nuclear") reset is unavoidable, the **pending offline queue must be preserved**
  — never wipe un-synced local edits.

- **CloudKit: explicitly out of scope.** Not supported; if you need it, you're on your own. (Also
  incompatible with the uniqueness model — see `docs/project/property-mapping-contract.md`.)

- **API stability: break freely.** No pre-1.0 stability constraint; breaking changes ship as a SemVer
  major bump. Don't over-engineer for source stability.

## Identity & change detection (decided)

**Model: `localId` + `remoteId` + `updatedAt`.** Every syncable row carries a client-generated
`localId` (always) and a `remoteId` (nil until the server has it). The data model itself classifies
and drives sync — no save-interception:

- **Missing `remoteId`** ⇒ local-only row ⇒ a pending *create* to push (it gets a `remoteId` on success).
- **Both ids, `updatedAt` newer than the last sync** ⇒ a pending *local update* to push.
- **Conflict** (a local row with both ids vs an incoming server row) ⇒ **latest `updatedAt` wins** (last-writer-wins).

So outbound detection is a **query over the store**, not interception of saves. (A spike confirmed you
*can* distinguish local-vs-sync writes via `didSave` + an "is-syncing" window — but the id model makes
that machinery unnecessary; detection is data-driven, which is simpler and more robust.)

Chosen over *client-UUID-becomes-the-server-id*: that's simpler (one id, a clean dictated contract)
but a hard requirement that limits adoption to greenfield apps. `localId`/`remoteId` is battle-tested
and works with any backend — with the known Core Data hazard to manage deliberately (id mutation +
thread-safety: never pass a model across contexts).

## Open question

- [ ] **SwiftData History API — optional optimisation, not the foundation.** Basic detection is the
      id + `updatedAt` query above. History could help *later* for efficient deltas and **delete
      tombstones** at scale; evaluate it then, on evidence — not now.

## Prior art (surveyed) — and what it changes

- **Legacy `Sync` (`DataFilter`):** inbound set-diff keyed by `localPrimaryKey` / `remotePrimaryKey`
  (local-not-in-remote ⇒ delete; remote-not-in-local ⇒ insert; intersection ⇒ update). Inbound only —
  the id mapping is the identity concept; its pain was rewriting references when a local id became a
  remote id (the Core Data "ids changed" breakage).
- **WatermelonDB:** client-generated stable ids (no remap); reserved `_status` + `_changed` columns;
  outbound is a *query* for `_status != synced`; soft-delete tombstones until the server acks;
  per-column "client wins" merge; all-or-nothing batch push with retry-once.
- **PouchDB ⇄ CouchDB:** client-chosen stable `_id`; `_rev` tree; changes-feed + resumable checkpoint;
  `_deleted` tombstone revisions; deterministic (clock-free) conflict winner, app resolves; pushes are
  idempotent/resumable.
- **Realm / Atlas Device Sync:** client-generated id; an *operation-log* changeset (not a query);
  field-level OT merge (deletes win, per-field LWW); client-reset escape hatch.

**Decisions and implications for our `localId` + `remoteId` + `updatedAt` model:**

1. **Decided: keep `localId` + `remoteId`.** The modern single-client-id systems (WatermelonDB / Couch /
   Realm) all *control both ends* — a different category. SwiftSync syncs **conventional JSON APIs**:
   backends it doesn't control, that mint their own ids on create. Single-client-id would require the
   backend to accept client UUIDs as canonical, narrowing SwiftSync to greenfield / controlled-backend
   apps. Two-id is the fit for our positioning (reach over existing backends *is* the point). The cost
   we knowingly own: the id-rewrite when `remoteId` arrives — reconcile references, and manage the
   thread-safety/mutability hazard (never pass a model across contexts). *(Only a deliberate
   repositioning to greenfield would flip this.)*
2. **Decided: `isDeleted` soft-delete.** A query for "missing `remoteId` / newer `updatedAt`" can't
   represent a deletion, so a deleted row keeps an `isDeleted` flag and stays in the store until the
   delete is pushed and the server acks; only then is it hard-deleted. (This is what "tombstone" means.)
3. **Make retried pushes idempotent.** Server upserts keyed by the client id; advance `lastSyncedAt` /
   clear the dirty condition only *after* the server acks; a client mutation-id lets the server dedupe.
4. **Whole-record `updatedAt` LWW loses concurrent different-field edits.** WatermelonDB (`_changed`)
   and Realm (OT) merge per-field. If a record can have concurrent writers, track `changedKeys` and
   merge per-field; if single-writer, whole-record LWW is fine — decide when we hit it.
5. **`updatedAt` wall-clock is clock-skew-fragile.** Prefer a server-authoritative timestamp, and a
   monotonic server cursor for "what changed since last sync" rather than a raw timestamp (records
   written in the same second as a sync can be missed).

## Next step — build the seam, slice by slice (each with its first real use)

Decisions are settled; implement the outbound seam in thin slices, each shipped with the thing that
exercises it (no plumbing-then-use-later):

1. **Offline-model contract + outbound detection.** A model declares `localId` (always), `remoteId`
   (nil until synced), `updatedAt`, `isDeleted`. First use: a query that partitions a store into
   pending **creates** (`remoteId == nil`), **updates** (`remoteId != nil`, `updatedAt` newer than last
   sync), and **deletes** (`isDeleted`). TDD it.
2. Pending-changes queue + push hook (app owns the network call); advance the sync cursor only on ack.
3. Failures table with discard / edit / retry.
4. Migration safety (the offline queue survives a nuclear reset).

Open: per-field vs whole-record LWW (#4 above) and the History-API optimisation — revisit on evidence.
