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

## Next step — design the public seam (study prior art first)

The outbound API — the syncable-model contract (`localId`/`remoteId`/`updatedAt`), the pending queue,
the push hook, the failures table — is a **public seam**, so study prior art before designing it: how
the old `Sync` did `localId`/`remoteId` (and where it hurt), plus WatermelonDB / PouchDB–CouchDB
replication / Realm sync. Then design *our* seam for *our* constraints and build it together with its
first real use — not plumbing now and a use case later.
