# Comment audit — full repo sweep

Repo-wide audit of code comments against the bar in the `comment-audit` skill and
`~/.claude/CLAUDE.md` (`## Comments`). Worked **section by section** (by context, not by file) so
each chop is reviewed with its surroundings visible.

## The bar

Every comment is **guilty until proven essential**. Default delete. Ties die. Doubt kills.

A comment lives **only** if it carries a fact that is all of:

1. unrecoverable from the code, names, and types;
2. stated nowhere else (keep at most one copy, at the declaration);
3. durable across refactors/renames/env changes (no snapshot rot);

…and is one of: external/wire-protocol knowledge, a non-obvious *why*, a gotcha the type system
can't express, a TODO with teeth, or a justification for suspicious-looking code.

- **Public-seam docs are not exempt.** A `///` that describes *what* a method does (recoverable from
  its name/signature) dies — public or not. Only a contract the signature can't express survives
  (ownership, threading, call-order, lifetime, magic-value meaning).
- Survivors are **trimmed to the load-bearing clause**.
- Where a comment exists because a *name* is weak, fix the name and delete the comment.

## Cadence

For each section: show the comments in context with a kill / trim / keep verdict, adjust, apply the
cuts, then build + `swift format` (no churn) + `swift test` green before moving on. Commit per
section (or per couple of sections) so the diff stays readable.

Baseline: ~685 comment-bearing lines across 38 files (crude count, over-counts multi-line `///`).

## Sections

- [x] **Section 0 — Library `SwiftSync/Sources` first (light) pass** — landed in #650 (merged).
  Cut 10 lines: a verbatim cross-call-site duplicate, three narration/restatement lines, two trims.
  Too timid; re-opened under the harder bar as Sections 1–2.

- [x] **Section 1 — Library public seam: doc comments**
  - Killed: `inboundAuthor` "Internal —" line; `localTransactions` doc (restatement); `SyncError`
    `invalidPayload`/`cancelled`/`containerInitialization` case docs (restate the case; `errorDescription`
    carries the text). Kept `schemaValidation` (names the non-obvious triggers).
  - Trimmed: `SyncPendingChanges` (cut field restatement, kept ids-not-objects contract); `SyncPushFailure`
    (cut idempotent-upsert dup of `withPendingChanges`); `withPendingChanges` (cut what-it-does opener);
    `SyncContainer.sync(item:)` (cut box sentence dup of `UncheckedSendableBox`).
  - Fixed stale refs: `` `push` `` → `` `withPendingChanges` `` (Core, PushHistoryTokenStore, Push ×2) —
    `push` was renamed to `withPendingChanges`; the backtick refs pointed at a symbol that no longer exists.
  - **API note (deferred):** the consumer operation reads as "push" in all prose but the method is named
    `withPendingChanges`. Consider a `push`-named entry point or doc alias — an API change, not a comment fix.
  - **Architecture (done, same branch):** `API.swift` held zero `public` declarations — it was the internal
    sync engine misnamed as the public layer (the public surface lives on `SyncContainer`/`Core`/`Push`/
    `ReactiveQuery`).
    - The reconcile engine became `ModelContext` methods: `context.sync(payload:/item:…)` in
      `ModelContext+Sync.swift`. The mutated thing is the receiver, so `in: context` threading is gone at
      ~205 call sites, and the `SwiftSync.sync` vs `SyncContainer.sync` verb collision evaporates. Domain
      calls inside the loop are explicit (`SwiftSync.identityKey(…)`) — opaque before, clear now.
    - All `SwiftSync`-static reconcile helpers consolidated into one `SwiftSync+Helpers.swift`
      (`normalize`/`resolveIdentity`/`identityKey`/`scopedIdentityKey`/`syncIdentityHasUniqueAttribute`/
      `fetchUniqueRow`/`resolveParent`/`isCancellation`/`withRelationshipLookupCache`) — no proliferation of
      `SwiftSync+X` files, no free functions.
    - `throwIfCancelled` deleted in favor of stdlib `try Task.checkCancellation()` (behavior-neutral — the
      `catch` already converts any cancellation → rollback → `SyncError.cancelled`).
    - Moved the inbound-pull local-edit helpers (`isUnsyncedLocalInsert`/`applyHonoringLocalEdit`) to
      `Push.swift` beside the dirty-set producers they consume.
    - **Serialization, judged from first principles:** the old per-container lease was a *global keyed
      singleton* (`private static let syncLeaseRegistry` keyed by `ObjectIdentifier(container)`) — a symptom
      of the engine being stateless statics with nowhere to hang per-store state. Replaced it: the engine
      `sync(...)` is now a pure reconcile function (no lease), and serialization is a per-instance async
      mutex (`SyncContainer.Serializer`, a nested `private actor` — `acquire`/`release` parented to the type,
      no singleton/global/keying) owned by `SyncContainer`, which wraps its four leaf `sync` methods. Contract: serialization is
      per-`SyncContainer` (one per store — the library's existing norm). Behavior-neutral: SwiftSync 48/48
      and DemoCore 43/43 (incl. ConvergingDrain/OfflinePush concurrency suites) green.
    - Naming nit left for later: `isUnsyncedLocalInsert` checks any dirty pid (created *or* edited), not
      just inserts.

- [ ] **Section 2 — Library internals: inline why/gotchas**
  - Same files, `//` inline (Core, SyncContainer, Push, SyncDateParser, SyncableMacro, SyncQueryPublisher) (~30)
  - Bar: keep only non-obvious *why* / gotcha / justification. Finish what Section 0 started.

- [ ] **Section 3 — Fake backend: the simulated server**
  - `DemoBackend/Sources/{DemoServerSimulator,DemoSeedData}` (~40)
  - Bar: wire-contract facts (LWW, upsert-by-`public_id`, idempotency) survive; endpoint narration dies.

- [ ] **Section 4 — Fake backend: tests**
  - `DemoBackendTests`, `UploadEndpointTests` (~44)
  - Bar: step-label narration (`// missing title`, `// older write loses`), MARK helpers.

- [ ] **Section 5 — App sync engine**
  - `DemoCore/Sources/{DemoSyncEngine,DemoAPI,ScreenMachines,DemoModels}` (~80)
  - Bar: offline/drain/failures *why* survives; restatement dies.

- [ ] **Section 6 — App sync engine: tests**
  - `DemoCore/Tests/*` (OfflinePush, ConvergingDrain, TaskForm…, TaskExportRegression, DirtyTrackingGap) (~80)
  - Bar: scenario doc-headers + step narration.

- [ ] **Section 7 — Demo app UI**
  - `Demo/Demo/{ContentView,TaskFormSheet,FailuresSheet}`, `Demo/DemoUITests` (~40)
  - Bar: real UI gotchas (safe-area inset reasoning) survive; UI-test KEPT-rationale + step narration scrutinized.

- [ ] **Section 8 — Library tests (largest; will sub-split)**
  - `SwiftSync/Tests/*` (~12 files, ~300)
  - Bar: tutorial headers, filename-restatement headers, Given/When step labels, MARK labels.
  - Known kills: `SyncRelationshipOperationsTests.swift:1` filename line + ~45-line `## Background /
    ## Why this exists / ## Historical note` header (the Historical note is snapshot rot);
    `SyncTests.swift` `// Seconds` / `// Milliseconds` / `// rename the first` step narration.

## Log

- Section 0: #650, merged.
- Sections 1–2 + engine restructure: #651 (draft). Full re-audit of `SwiftSync/Sources/` (128 comment
  lines) after the restructure: the explanatory doc + inline comments survive the bar (SwiftData/CoreData
  quirks, the SQL `nil != "inbound"` trap, provenance, invariants, justifications) — Section 1 + the
  restructure already removed the restatement/duplication. Found one partial-duplicate trim
  (`SyncContainer` schema-registration comment) and cut 5 access-level `// MARK:` headers in
  `SyncQueryPublisher` (they restated `public`/`private`); kept Core.swift's 2 navigation MARKs (1300-line
  file). This closes Section 2 (library inline comments) — the surface is fully audited.
