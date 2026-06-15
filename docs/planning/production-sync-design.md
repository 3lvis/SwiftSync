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

## Open forks (resolve before/while implementing)

- [~] **Identity strategy — leaning `localId` + `remoteId`.** Client-UUID-becomes-the-server-id is
      simpler (one id, minimal bookkeeping, a clean dictated contract) but is a *hard* requirement that
      effectively limits adoption to greenfield apps. A `localId` + `remoteId` mapping is battle-tested
      and works for existing apps / any backend; the historical pain was Core Data breaking when an id
      changed — thread-safety + mutability red zones (never pass a model across contexts) — but that was
      solved before with a lot of effort. **Leaning localId + remoteId for the broader reach; manage the
      identity-mutation/threading hazard deliberately. Confirm before building on it.**

- [ ] **Change detection — build our own plumbing first, then evaluate History.** To avoid biasing
      toward a new and possibly-fragile API: implement our *own* outbound change-tracking first and get
      it working, then see where the SwiftData History API can connect to / reduce its complexity.
      Own-first; History as an optional optimization, decided on evidence, not a guess.

## Proposed first step — own-plumbing change detection (spike)

Build our own outbound change-tracking: capture **app-originated** local edits into a pending-changes
queue, keyed by `localId` / `remoteId`. Time-boxed and exploratory.

The central question it must answer: **how to tell an app-originated (local, queue-it) mutation from a
sync-originated (server) one**, so only real local edits go outbound. Candidate to validate: a
`ModelContext` save that happens *outside* a `SwiftSync.sync()` operation is a local edit.

Once it works, evaluate where the History API could simplify it. Then break the accepted areas
(queue, failures table, migration safety) into their own implementation PRs.
