# Folding DemoSyncEngine's boilerplate into SwiftSync

## Goal

`DemoSyncEngine` (~490 lines) carries a lot of machinery that **every** SwiftSync consumer would
rewrite identically: push-queue draining, failure/pending surfacing, reconnect handling, and
operation de-duplication. Fold that machinery into the library so the demo's engine expresses only
**app intent** — the wire format, which endpoints to pull, and the app's offline write choices —
not the plumbing around it.

The felt result for a consumer: register a transport once, edit/save normally, and never hand-write
the drain / failure / reconnect loop again.

## The model we are keeping (read this before touching anything)

The demo already does writes **properly**, and we are **not** changing that:

- **Online writes are network-first.** Call the server, let it confirm, *then* sync the confirmed
  result into the store. Errors are synchronous and inline (the form shows them). This is the correct,
  server-authoritative UX and it stays.
- **Offline writes are optimistic + queued.** Apply locally, queue, push on reconnect. This already
  exists and stays.

We are folding the **mechanical scaffolding** that is identical regardless of which of those two paths
runs — not unifying the two paths, and not making online writes optimistic.

## Non-goals (explicitly rejected — do not reintroduce)

- **No "all writes become optimistic."** An earlier draft proposed routing every write through the
  queue; that would downgrade the online UX (lose synchronous validation). Rejected.
- **No auto-push-on-`save()` as the universal trigger.** Online writes are gated by the network, not by
  `save()`. The auto-drain applies only to the *pending queue* (offline / un-pushed changes), on
  reconnect or on demand.
- **No `syncState` observable / per-row status type.** That was a consequence of the optimistic model.
  The demo surfaces failures via its own field and inline errors; that is enough.
- **No debounce engine.** Only relevant if `save()` auto-fired pushes, which it does not.
- **No retry/backoff in SwiftSync.** Resilience (`Retry-After`, backoff, auth refresh) is the
  networking layer's job, wired into the consumer's transport. The library only *triggers* a drain
  (on demand / on reconnect) and de-duplicates.

## Dependencies & base

Built on the push-seam work in **#644** (`withPendingChanges` + `process` closure returning
`[SyncPushFailure]`). The total-accounting variant (#645, `[String: SyncRowOutcome]`) was dropped, so
`SyncBackend.push` returns `[SyncPushFailure]`. Start this once #644 merges, and branch off master.

## Revised architecture (decided during implementation)

- **No separate `SyncEngine` type — `SyncContainer` absorbs the outbound machinery.** It's the object
  the app already injects, so it owns `register(_:for:)`, `drain() -> [SyncPushFailure]`, `isOnline`
  (auto-drains on reconnect), and an `onDrainComplete` handler for the reconnect result. The
  `sync(payload:)` path and the cross-thread `@objc` did-save handler are left untouched, so bulk sync
  stays off-main and `SyncContainer` stays a plain `@unchecked Sendable NSObject` (no `@Observable` /
  `@MainActor` reshuffle, no unsound `@unchecked` + observable-state combination).
- **Counts are NOT library state.** `pendingCount` / `failedCount` are a UI concern the app derives from
  the existing `pendingChanges` primitive + the failures `drain()` returns. The library keeps no UI
  state. (Shipped: library side done — `SyncContainerOutboundTests`, 175 green.)

## Sequencing principle

Work **section by section**, not micro-task by micro-task. Each section is one self-contained,
green, reviewable unit (a PR or short series). Strict red-first TDD applies to every `SwiftSync/**`
change; the demo layer follows the repo's lighter demo-app rules but must build. Each section ends
with the demo strictly smaller than it started and all tests green.

---

## Section 1 — Discovery: map the demo end-to-end

Before folding anything, confirm what is genuinely boilerplate vs. app logic by tracing every call
site, so we relocate real duplication rather than shuffling app intent around.

- [ ] List every caller of `DemoSyncEngine` (screens / `ScreenMachines` / views): which methods, and
      whether they hit the online or offline branch.
- [ ] For each engine method, classify its lines as **Fold** (mechanical, identical across apps),
      **Keep** (app-specific: wire format, endpoint choice, scoping/backfills), or **Collapse**
      (dead once a fold lands).
- [ ] Confirm the online network-first flow and the offline apply-local flow are both exercised by
      existing tests (DemoCore + any UI test) so we have a green baseline to protect.

**Done when:** a short Fold/Keep/Collapse inventory is recorded here and the baseline test set is
identified.

**Result (done).** Callers traced across `ScreenMachines` + the Demo app:
- **Fold:** `pushPendingChanges` (engine) + the manual reconnect drain in `ContentView.onChange(of: isOffline)`;
  `pendingChangeCount` / `failedChangeCount` (read by `ContentView` badges + `FailuresSheet`) → library-derived;
  `annotateFailures` / `refreshPendingCount`; `inFlightOperations` / `runOperation` / `pull` de-dup + offline-swallow.
- **Keep:** the write methods' online/offline branching (called by `ScreenMachines`); the pull data methods
  (which endpoint, scoping, backfills); `discardFailedChange` (app inbox action); `failedTasks()` (inbox query);
  the `isOffline` toggle (app UI — becomes the reachability signal); the wire format (`upload`/`taskData`).
- **Baseline tests:** DemoCore `OfflinePushTests` (offline create/update/delete/discard round-trips) + the
  DemoUITests offline flow + SwiftSync `OfflinePushTests`/`OfflineHistoryTests`.

---

## Section 2 — Extract the transport as a registered `SyncBackend`

Turn the demo's inline `upload` / `taskData` into a transport object the container holds, so the
push machinery has something to call without the app passing a closure each time.

- [ ] Add `public protocol SyncBackend { func push(_ pending: SyncPendingChanges) async throws -> [SyncPushFailure] }`.
- [ ] Add registration on the container (`register(_:for:)` or a `backend` property).
- [ ] Move the demo's `upload(_:)` + `taskData(_:)` into a `TaskBackend: SyncBackend` (logic unchanged).
- [ ] Behavior-preserving: the engine still drives the push, but through the registered backend.

**Done when:** the demo's push path calls the registered `TaskBackend`; no behavior change; SwiftSync
+ DemoCore green.

---

## Section 3 — Library-owned queue drain + reconnect

Fold the push orchestration and the "drain on reconnect" wiring into the library. This is the core
of the magic: the consumer stops hand-writing the drain loop.

- [ ] Add a library drain entry that runs `withPendingChanges` through the registered backend for
      each offline model, on demand.
- [ ] Own the de-duplication / in-flight guard so concurrent drains coalesce (replaces the demo's
      `inFlightOperations` for the push key).
- [ ] Auto-trigger a drain when the app's reachability signal flips offline→online (the library takes
      a signal; it does not own a network monitor).
- [ ] Delete the demo's `pushPendingChanges`, its in-flight bookkeeping for push, and the manual
      "push before pull" / reconnect triggers that the library now owns.
- [ ] TDD (SwiftSync/**): a drain de-dups concurrent calls; a reconnect signal triggers exactly one
      drain; an offline drain is a no-op.

**Done when:** the demo no longer contains push-drain or reconnect-trigger code; queue drains on
reconnect automatically; all green.

---

## Section 4 — Fold failure & pending surfacing

Replace the hand-maintained counts and the failure-annotation dance with library-exposed values
derived from the pending set + the last drain's failures. Keep it minimal (no new observable status
type — see non-goals).

- [ ] Expose pending and failed counts (and the failed id set) from the library, derived from
      `pendingChanges` + the most recent drain failures.
- [ ] Decide the failure surface: either the library exposes the failed `[SyncPushFailure]` for the
      app to render, or the demo keeps its `syncFailureReason` field but stops hand-maintaining counts.
      Pick the smaller option that keeps the demo's failures inbox working.
- [ ] Delete the demo's `annotateFailures`, `refreshPendingCount`, `pendingChangeCount` /
      `failedChangeCount` bookkeeping, and `failedTasks` plumbing made redundant.
- [ ] TDD (SwiftSync/**): counts reflect pending minus failed; failed set matches the last drain.

**Done when:** the demo reads counts/failures from the library; its inbox still works; all green.

---

## Section 5 — Operation runner — **not folded (deliberate)**

The pull-side scaffolding (`runOperation` de-dup + `pull` swallowing offline) does **not** generalize
cleanly into the library: the offline-swallow keys off `DemoAPIError.offline`, an app-specific error the
library can't know, and the dedup is keyed by app-chosen operation names. Per "earn the abstraction," it
stays a demo helper. (A future generic seam could take an `isOffline` predicate, but there's no second
consumer to justify it yet.)

---

## Section 6 — Cleanup, docs, verification — **done**

- [x] No dead demo code; the per-resource REST endpoints stay (online writes still use them).
- [x] README + this doc updated; `world-class-roadmap.md` points here.
- [x] Demo app builds on a dynamically-selected simulator; DemoCore 42 / DemoBackend 30 / SwiftSync 175 green.

---

## Outcome

- **Library (`SyncContainer`):** `SyncBackend` + `register(_:for:)` + `drain() -> [SyncPushFailure]` +
  `isOnline` (auto-drains on reconnect) + `onDrainComplete`. No UI state; off-main `sync(payload:)` and the
  did-save handler untouched; stays a plain `@unchecked Sendable NSObject`.
- **Demo:** `upload`/`taskData` → `TaskBackend: SyncBackend`; `pushPendingChanges` → `syncContainer.drain()`;
  `isOffline` drives `isOnline`; `ContentView`'s manual reconnect `onChange` deleted. `DemoSyncEngine` shed
  the push orchestration/transport/reconnect (−112 lines in that file). The demo keeps its own counts +
  `syncFailureReason` inbox (a UI concern, re-stamped via the drain result + `onDrainComplete`).

## Resolved questions

- **Failure surface (Section 4):** the app keeps its `syncFailureReason` field; the library returns the
  drain's `[SyncPushFailure]` (directly + via `onDrainComplete`). Lower risk than removing the field.
- **Operation runner (Section 5):** stays a demo helper (app-specific offline error / keys).
- **Reachability (Section 3):** a plain `Bool` (`isOnline`) the app sets — mirrors the demo's `isOffline`.
- **Counts:** **not** library state — the app derives them from `pendingChanges` + the drain failures.
