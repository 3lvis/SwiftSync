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

- **Observability: net-new structured hooks.** SwiftSync has *no* `print`/logging in its library
  source today (earlier "remove print" note was a mix-up with the Networking repo). Add structured
  hooks for the sync lifecycle — started / progress / succeeded / failed, with errors — so apps can
  log/surface sync state. Additive, not a rework.

- **Schema migration: optimistic, with offline-safe nuclear option.** Prefer lightweight migrations;
  when a destructive ("nuclear") reset is unavoidable, the **pending offline queue must be preserved**
  — never wipe un-synced local edits.

- **CloudKit: explicitly out of scope.** Not supported; if you need it, you're on your own. (Also
  incompatible with the uniqueness model — see `docs/project/property-mapping-contract.md`.)

- **API stability: break freely.** No pre-1.0 stability constraint; breaking changes ship as a SemVer
  major bump. Don't over-engineer for source stability.

## Open forks (resolve before/while implementing)

- [ ] **Identity strategy for offline-created rows.** Preferred: **client-generated UUIDs that become
      the server id** — the app and backend both use UUID ids; SwiftSync pushes the offline UUID and it
      *is* the remote id (one id, minimal bookkeeping; a dictated contract). Alternative (debatable):
      keep a separate **localId + remoteId** mapping (as the very old offline implementation did) —
      more bookkeeping, but doesn't require backend UUIDs. **Decide.**

- [ ] **Change detection: SwiftData History API vs. our own plumbing.** Spike the History API first;
      adopt it if it's ergonomic and reliable (low consumer ceremony). It's new, so if it's cumbersome
      or breaks easily, fall back to our own change-tracking plumbing. **It depends — resolve by spike,
      not by guess.**

## Proposed first step

A **time-boxed spike**: implement outbound change detection two ways — (a) via the SwiftData History
API, (b) via a minimal own-plumbing approach — on a representative model, and compare on consumer
ceremony and reliability. The result picks the foundation. Throwaway code; the finding is the
deliverable. Then break the accepted areas (queue, failures table, observability hooks, migration
safety) into their own implementation PRs.
