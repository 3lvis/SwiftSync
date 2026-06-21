# Push/Drain Pipeline — Review & Test-Harness Plan

> **Status:** plan only — no fix committed yet. This doc is the handoff for a *fresh session*; it assumes
> no memory of the conversation that produced it. Read it top to bottom and you have everything.

## 0. Why this doc exists

A review of PR #646 surfaced two findings in the offline push/drain pipeline (P1, P2 below). The first
attempt to fix them went wrong in an instructive way:

- P1 was "fixed" by serializing drains into a chain **before writing a failing test**. The fix even looked
  *correct-by-construction* — which is the trap, not the proof.
- The test fixture built to pin P1 was a global, one-shot gate actor. It **deadlocked twice** because the
  drain logic hit the gate more than once and the gate only opened once.
- A `for 0..<8` re-drain loop (with an arbitrary cap of 8) was added to paper over late arrivals — solving
  a problem that only existed because the seam was wrong.
- The P2 "fix" edited the offline-no-op test to read the server **while still offline** — but the demo
  transport throws `.offline` on every call when offline (`FakeDemoAPIClient.networkGate`), so that read
  throws instead of returning `nil`. The edit was broken, and a second added assertion tested
  pre-existing reconnect behavior (green-from-birth, which this repo forbids).

Both attempts were **reverted**. The lesson the owner drew: *the bug is not structurally untestable — a
deadlocking fixture means the test boundary is wrong.* This plan exists to find the **right** boundary
first, then redo P1 and P2 the disciplined way (red-first).

**Guiding principle for the whole effort: build the deterministic test harness first. The harness is the
deliverable; the two fixes are its first two customers.**

## 1. The system under review (how push/drain works today)

All paths below are by *role*, not hard path (files move). Names are current as of this writing.

- **`SwiftSync` (pure storage).** `SwiftSync.withPendingChanges(for:in:){ process }` reads the pending set
  from SwiftData history (a token boundary), runs `process(pending)`, and advances the history token
  **only on a clean return** (it returns the `[SyncPushFailure]` the closure produced; a throw leaves the
  token un-advanced so the batch is retried). `SwiftSync.pendingChanges(for:in:)` reads pending without
  advancing.
- **`DemoSyncEngine` (orchestration + networking).** `@MainActor @Observable`. Owns app-wide sync status
  (`isOffline`, `isSyncing`, `pendingChangeCount`, `failedChangeCount`) and the failures inbox.
  - **Online write:** network-first — confirm with the server, then sync the response locally.
  - **Offline write:** optimistic local apply, queued as a pending change.
  - **Reconnect:** `isOffline`'s `didSet` (engine, ~line 31) flips `apiClient.isOffline` and, on
    `true → false`, fires `_Concurrency.Task { try? await pushPendingChanges() }` to drain the queue.
    (`_Concurrency.Task` is aliased because `Task` is a demo *model* type.)
- **`pushPendingChanges()` — the drain (engine, ~line 204), CURRENT shape:**

  ```swift
  public func pushPendingChanges() async throws -> [SyncPushFailure]? {
      guard !isOffline else { return nil }
      if let activeDrain { return try await activeDrain.value }   // <-- COALESCE (the P1 bug lives here)

      let task = _Concurrency.Task { @MainActor in
          try await SwiftSync.withPendingChanges(for: Task.self, in: syncContainer.mainContext) { pending in
              try await self.upload(pending)
          }
      }
      activeDrain = task
      defer { activeDrain = nil }
      ...
      let failures = try await task.value
      try annotateFailures(failures)
      refreshPendingCount()
      return failures
  }
  ```

- **`upload(_ pending:)` (engine, ~line 231):** turns the pending batch into `/sync/upload` operations,
  calls `apiClient.upload(operations:)` **once**, and returns only the rejected rows. `stale` ⇒ server won
  LWW (adopt its state, not a failure); `applied` ⇒ ok; anything else ⇒ a `SyncPushFailure`.
- **`FakeDemoAPIClient` (DemoCore/Networking):** the demo transport. `networkGate(endpoint:)` throws
  `DemoAPIError.offline` when `isOffline`, else applies scenario delay/flakiness. `upload(operations:)`
  forwards to the in-memory `DemoServerSimulator`.

## 2. The two findings under review (reviewer's words)

- **P1 — coalescing can strand a newer edit.** "If an offline-created row is edited while the reconnect
  drain is uploading its previous version, `updateTask` joins `activeDrain`. That drain only covers its
  original history boundary, so the newer edit remains pending and no second drain runs." The coalesce at
  line 208 returns the *in-flight* drain's result to the later caller; that drain's `pending` set was read
  before the later edit existed, so the later edit is never uploaded and no drain ever sees it.
- **P2 — the offline no-op test races reconnect's automatic upload.** `testOfflineCreatePushIsNoOpWhileOffline`
  sets `isOffline = false` (which schedules the reconnect drain) and *then* asserts the server still lacks
  the row — a race against the auto-drain.

### Current state of the tree (post-revert)

- P1: **not fixed** — `pushPendingChanges` still coalesces (the buggy version above).
- P2: **not fixed** — the test still has the race.
- **Kept** (NOT reverted, per owner's explicit scope): the P2-*doc* fix in `architecture.md` (correcting
  two layering overstatements — see §6) and this plan + its roadmap pointer.

## 3. Root cause of the testing pain (first principles)

These are **ordering** bugs, not **timing** bugs. The strand only manifests for a specific *interleaving*:
an edit must land **after** a drain reads its pending boundary but **before** that drain finishes. Trying
to reproduce that with `sleep`/delays is inherently flaky and is what produced the deadlock-and-loop mess.

To test ordering deterministically you must **control execution order**, not wall-clock time. The unit
needs a synchronization point it owns: "pause the upload here, let me do something, then proceed." The
earlier gate deadlocked because it was **global and one-shot** while a correct drain may upload **N times**
(once per drain). The seam must therefore support **per-upload** handshakes, not a single global latch.

## 4. The test harness (the "easy way" to reproduce → fix)

**Design: an injectable, controllable upload seam on `DemoSyncEngine`.** `pushPendingChanges` already
funnels all networking through one private `upload(_ pending:)` → `apiClient.upload(operations:)`. Lift
that into an overridable seam so tests can substitute a controllable implementation.

Two candidate shapes (decide in the harness step — prefer the smaller one that keeps production untouched):

1. **Inject the upload closure** into `DemoSyncEngine.init` (default = the real one). Tests pass a
   controllable closure. Most explicit; touches the initializer signature.
2. **Make `FakeDemoAPIClient.upload` controllable** behind a test-only hook (a closure the test installs).
   Production engine code is untouched; the control lives entirely in the fake transport.

**The controllable upload primitive** (continuation handshakes, not sleeps):

```swift
// Test-side. One "started" signal + one "proceed" gate PER upload call — never global/one-shot.
actor UploadController {
    // For each upload: notify the test it began, then suspend until the test releases it.
    func onUploadStarted() async        // test awaits this to know a drain is mid-flight
    func releaseNextUpload()            // test calls this to let a parked upload finish
    // backed by per-call CheckedContinuations queued in FIFO order
}
```

**The P1 strand reproduction (the red test):**

1. Create row A offline; reconnect → drain 1 starts, its upload **signals started and parks**.
2. The test, now certain drain 1 is mid-flight (it awaited `onUploadStarted`), **edits row A** (the "late"
   edit) and calls `pushPendingChanges()` again.
3. The test **releases** drain 1's upload; lets things settle.
4. **Assert:** the late edit reaches the server (and `pendingChangeCount == 0`). With today's coalesce this
   **fails** (the late edit is stranded) ⇒ red for the right reason.

This is robust because the interleaving is enforced by continuations the test owns — deterministic, no
caps, no sleeps, and it supports the multiple uploads a correct fix performs.

**The P2 rewrite (deterministic, no harness needed):** the offline no-op is *fully* proven by engine state
**while offline** — `pushPendingChanges()` returns `nil` and `pendingChangeCount` stays `1`, with zero
network. The server-read was always both racy (vs auto-drain) and redundant. The fix is to **delete** the
reconnect-and-read tail, not add to it — leaving a smaller test that says exactly what its name claims. (A
*separate* test, built on the harness, can assert "reconnect drains the queue" deterministically if that
coverage is wanted — but it must be red-first against a real gap, not green-from-birth.)

## 5. Methodology (red-first — repo law, no exceptions)

Per `SwiftSync/CLAUDE.md` and `~/code/3lvis/ios/CLAUDE.md`, for **every** behavior change:

1. Write/adjust the test. 2. Run it; **paste the red**. 3. Confirm it fails for the *expected* reason
(right assertion, not a compile error). 4. Only then touch source. 5. Re-run; **paste the green**.
Never edit source and test in the same step. "Correct-by-construction" is **not** a substitute for red.

## 6. Ordered work plan

1. **Harness.** Build the controllable upload seam + `UploadController` in DemoCore tests. No behavior
   change — just the seam and a smoke test that a parked upload blocks and releases on command.
2. **P1 red→green.** Write the strand repro (§4) → confirm red → implement the minimal fix that greens it.
   Let the *test* decide the fix shape (serialize-and-re-drain-current, loop-until-pending-empty, or
   re-run-on-join); do **not** pre-commit to the chain. Paste red, then green.
3. **P2 deterministic rewrite.** Strip the racy server-read; assert the no-op via offline engine state.
   Run the suite green. (Add a separate harness-based reconnect-drains test only if it guards a real gap.)
4. **Re-evaluate the P2-doc fix** already in `architecture.md`: (a) the engine *does* use SwiftData
   directly for plain local reads/writes (the box no longer claims it doesn't); (b) not every screen has a
   machine — `FailuresSheet` hosts its query directly (the doc now says "data is a reactive query, status
   is modelled where a lifecycle exists"). Confirm these read true after the code review, adjust if not.
5. **Land PR #646 properly.** It still has merge conflicts and a stale title/body ("Fold outbound sync
   into SyncContainer; demo pushes via register/drain" — describes a *reverted* architecture). Rebase onto
   `origin/master` (now at `bf7dac27`, #644 squashed; the conflict is the push-seam files — take master's
   side where content matches), rewrite the title/body to the actual change (FailuresSheet reactive query +
   architecture doc), then full verification (SwiftSync / DemoCore / DemoBackend `swift test` + demo build)
   and the simulator tier (mark ready) before any merge. **Never merge without an explicit ask.**

## 7. Open questions for the new session

- **Seam shape:** inject the upload closure into the engine (option 1) vs a test hook on the fake transport
  (option 2)? Lean to whichever keeps production code untouched while still letting the test interleave a
  *real* drain.
- **P1 fix shape:** what's the minimal change that greens the strand test *and* preserves the reason
  coalescing existed (a push-before-pull must not race a concurrent reconnect upload)? Serialization is
  likely still needed — but it must also drain the *current* pending set on each call, which coalesce
  doesn't. Decide against the test, not in the abstract.
- **Doc scope:** keep the `architecture.md` P2-doc edits in this branch/PR, fold them into #646, or revert
  and let the review redo them?

## 8. Pointers

- `DemoSyncEngine` — `pushPendingChanges` (~204), `upload(_:)` (~231), `isOffline.didSet` (~31),
  `activeDrain` (~47).
- `OfflinePushTests.testOfflineCreatePushIsNoOpWhileOffline` — the P2 test.
- `FakeDemoAPIClient` — `upload(operations:)`, `networkGate` (offline throw).
- `SwiftSync.withPendingChanges` / `pendingChanges` — the token-bracketed storage primitive.
- PR **#646** (draft, base `master`), branch `docs/sync-engine-fold-plan`. This plan lives on
  `docs/push-drain-review-plan`, branched from it.
- The reverted P1/P2 attempt is recoverable from this branch's reflog / the PR discussion if a detail of
  the chain approach is wanted.
