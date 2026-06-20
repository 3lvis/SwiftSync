# UI Test Trial — put every UI test on trial

## Why

The `DemoUITests` suite is the most expensive thing in CI: it boots a simulator, builds the app, and
drives the UI serially — ~10 minutes for the whole suite (the ready-gated `iOS Simulator Tests` job from
PR #633). That cost is only worth paying for a regression **nothing cheaper can catch**.

Two anti-patterns have crept in and must go:

1. **Green-at-birth tests.** A test that passed the moment it was written guards nothing — it never
   demonstrated it can fail for the reason it claims to. 10 of the 15 UI tests arrived in a single
   492-file bulk rewrite (`7ab19239` "Replace legacy Sync with SwiftSync codebase"), created alongside
   the feature, not red-first. These are prime suspects.
2. **UI tests for logic a unit test can catch.** A CRUD round-trip or an offline-sync rule is engine
   behavior; it belongs in a DemoCore/DemoBackend/SwiftSync unit test, which runs in milliseconds on
   every push. Precedent: the dirty-tracking regression *started* as a UI test and was driven down into
   `DirtyTrackingGapTests` (a DemoCore test on the simulator) — that conversion is the model.

This plan puts **every** UI test on trial, systematically, with a strong bias toward removing or
converting — but never removing blindly. A UI test survives only with a demonstrated, documented reason.

## Rules (to encode in AGENTS.md)

- **R1 — A UI test owns its timeouts inline.** No shared timeout constant across tests. Each
  `waitForExistence`/`waitForNonExistence` carries a value sized for *that* test's operation, at the call
  site. (First concrete task: delete `saveDismissTimeout` and inline a per-call value.)
- **R2 — No green-at-birth tests.** A test earns its place only by having been **red before** the fix it
  guards. A test that passed at creation, guarding no demonstrated failure, is removed. (This is the
  red-first rule from AGENTS.md, applied retroactively as an audit.)
- **R3 — Prefer the cheapest layer that reproduces the failure.** Before keeping a UI test, try to make
  the core failure reproduce as a DemoCore/DemoBackend/SwiftSync unit test. If a unit test catches it,
  the UI test is redundant — drop it.
- **R4 — Keep a UI test only with a strong, documented reason.** It must exercise something units
  genuinely cannot (real view hierarchy, navigation between screens, a SwiftUI binding/reactivity path, a
  gesture, a cancel/dismiss affordance) *and* you have tried and failed to pin it to a unit. State the
  reason in a one-line comment on the test.

## Trial procedure (run per test)

For each UI test `T`:

1. **Locate its shape.** `git blame` the declaration; read the introducing commit's intent. A test born
   in a bulk feature commit (no separate red step) is a green-at-birth suspect.
2. **Red-first check.** Reconstruct whether `T` was red before its guarding fix: revert the fix (or check
   out the introducing commit's parent) and run `T`. If `T` cannot be shown to have ever failed for its
   stated reason → **remove** (R2). Paste the (non-)failure.
3. **Pin to a unit.** Name the core behavior `T` asserts. Write/point to a unit test that fails for the
   same reason (red), then make it green.
   - Unit reproduces it → once unit + `T` are both green, **drop `T`** (R3).
   - Unit cannot reproduce it (failure is genuinely UI-layer) → one more honest attempt → if still not,
     **keep `T`** with a documented reason (R4).
4. **Record** the verdict + evidence in the trial log section below.

Batch the work (one PR per cluster, smallest first); never bundle a UI-test deletion with unrelated
changes. Re-run the `iOS Simulator` gate after each batch.

## First-pass inventory (15 tests)

Existing unit coverage to lean on: `OfflinePushTests` (17 offline/conflict/failure cases),
`TaskFormPeopleMutationTests` (online people edits), `ScreenStateResolutionTests` (loading/empty/error/
content states), `TaskFormDescriptionNormalizationTests`, `TaskExportRegressionTests`, `DirtyTrackingGapTests`.

| # | UI test | Shaped | Exercises | Existing unit overlap | Preliminary verdict |
|---|---|---|---|---|---|
| 1 | testProjectAndTaskDetailShowSeededContent | bulk `7ab19239` | seeded content renders in list + detail | ScreenStateResolutionTests (content states), engine sync | **Convert/drop** — sync+fetch+state, no UI-only fact |
| 2 | testUpdateTaskTitleKeepsProjectAndDetailInSync | bulk | title edit reflects in list *and* detail | OfflinePushTests update; SwiftSync @SyncQuery reactivity | **Investigate** — cross-screen reactivity may be the only UI-real part |
| 3 | testCreateTaskInsideProject | bulk | create flow | engine createTask, OfflinePushTests create | **Convert/drop** |
| 4 | testEditTaskItemsFlow | bulk | items add/rename/delete | none specific (items mutation) | **Convert** — engine update-with-items unit |
| 5 | testEditTaskPeopleFlow | bulk | assignee+reviewer+watcher edit | TaskFormPeopleMutationTests (exact) | **Drop (redundant)** |
| 6 | testAssignUnassignedTask | bulk | set assignee | people-mutation unit | **Convert/drop** |
| 7 | testDeleteTaskFromProject | bulk | delete task | OfflinePushTests delete, engine delete | **Convert/drop** |
| 8 | testCancelCreateDoesNotPersistTask | bulk | cancel create persists nothing | none (form machine) | **Convert** — TaskFormSheetMachine cancel unit |
| 9 | testCancelEditKeepsOriginalTaskValues | bulk | cancel edit discards changes | none (edit-context discard) | **Convert** — editContext discard unit |
| 10 | testClearTaskReviewersOrWatchers | bulk | clear reviewers/watchers | people-mutation unit | **Drop/convert (redundant)** |
| 11 | testOfflineCreateQueuesThenSyncsOnReconnect | #620 | offline create → reconnect → sync | testOfflineCreateThenPushStampsRemoteID… | **Pin to unit**; keep only if offline-toggle+pending-count UI is the point |
| 12 | testOfflineEditTaskTitleUpdatesProjectList | #622 | offline edit → list updates | testOfflineEditOfCreatedTaskUpdatesTitle… | **Pin to unit**; list reactivity maybe UI |
| 13 | testRejectedOfflineEditAppearsInFailuresInboxAndDiscards | #622 | failures inbox surface + discard | testRejectedPushPersistsFailureReason…, testDiscardFailedChangeRestoresServerState… | **Drop core (redundant)**; inbox rendering only UI-specific part |
| 14 | testOfflineAddReviewerSyncsOnReconnect | #621 | offline reviewer → sync | testOfflineReviewerAssignmentRoundTrips…, testOfflineUpdateTaskWithReviewerIDsAppliesLocally | **Drop (redundant)** |
| 15 | testOfflineDeleteQueuesThenSyncsOnReconnect | #620 | offline delete → sync | testOfflineDeleteThenPushHardDeletes… | **Drop/convert (redundant)** |

## Redundancy clusters (first pass)

- **People/relationships** (5, 6, 10, 14): now substantially covered by `TaskFormPeopleMutationTests` and
  the offline-reviewer unit tests. Strongest drop/convert cluster.
- **Offline round-trips** (11, 13, 14, 15): overlap `OfflinePushTests` heavily; the engine behavior is
  already unit-tested. UI-specific residue is the offline toggle, pending-count badge, and failures inbox.
- **Basic CRUD** (1, 3, 4, 6, 7): engine + state-resolution units cover the logic; little UI-only value.
- **Cancel/dismiss** (8, 9): form-machine behavior, convertible to machine unit tests.

## Suggested execution order

1. **R1 first** — inline timeouts, delete `saveDismissTimeout` (mechanical, unblocks the rest).
2. **Clear redundant drops** — 5, 14 (people/reviewer already unit-covered): confirm unit green, drop UI.
3. **Offline cluster** — 11, 13, 15: confirm `OfflinePushTests` coverage, drop/convert.
4. **CRUD converts** — 1, 3, 4, 6, 7: pin to engine units, drop UI.
5. **Cancel converts** — 8, 9: machine unit tests.
6. **Genuine-UI keepers** — 2, 12 (cross-screen reactivity): try hard to unit-cover @SyncQuery propagation;
   keep with a documented reason only if not.

## Guardrails

- **Strong reason or it goes.** "It's nice end-to-end coverage" is not a reason. The reason must name the
  UI-only fact and cite the failed unit attempt.
- **Document every kept UI test** with a one-line why (R4).
- **Red-first, always** — converting down means the new unit test must be red before the fix it inherits,
  or (for already-green behavior) it must be a genuine contract the code can break.
- The dirty-tracking conversion (`DirtyTrackingGapTests`) is the template for "drove a UI test down to a
  cheaper layer."

## Trial log

(Filled in as each test goes through the procedure: test, was-it-red-first evidence, unit attempt + result,
verdict, PR.)

- _pending_
