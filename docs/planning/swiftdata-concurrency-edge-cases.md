# SwiftData Concurrency and Store Edge Cases

Internal planning/test-tracking document.
User-facing behavior guarantees should be documented in `README.md` and `docs/project/faq.md`.

Purpose: capture high-impact real-world edge cases and define optimistic, deterministic outcomes (`last-write-wins`, queued writers, safe fallback paths) so we can validate them one by one in SwiftSync.

Status legend:

- `[ ]` not started
- `[-]` in progress
- `[x]` complete

## P0: Core Reliability Guarantees

### [x] 1. Concurrent sync on the same `ModelContext`

- Test name: `testConcurrentSyncSameContextCausesRaceOrConflict`
- Real-world scenario: pull-to-refresh and websocket event trigger sync at the same time.
- Setup:
  - Use one `ModelContext`.
  - Start two concurrent sync calls with overlapping IDs.
- Expected behavior:
  - Continuous safe operation under concurrency.
  - No overlap on the same `ModelContext`; concurrent requests are queued.
  - Deterministic final state by execution order (last queued writer wins).
- Why DataStack helped:
  - Writer context serialization prevented concurrent mutation races.

### [x] 2. Concurrent sync on different contexts targeting one store

- Test name: `testConcurrentSyncDifferentContextsSameStoreUniqueConstraintConflict`
- Real-world scenario: foreground edit and background import save simultaneously.
- Setup:
  - Create two `ModelContext` instances on one `ModelContainer`.
  - Both write rows with the same unique ID.
- Expected behavior:
  - Continuous safe operation under concurrency.
  - No overlap across contexts that share one store/container; requests are queued.
  - Deterministic final state by execution order (last queued writer wins).
- Why DataStack helped:
  - Explicit merge policy and save funnel reduced ambiguous conflict outcomes.
- SwiftSync status:
  - Covered by test `testConcurrentSyncDifferentContextsSameStoreUniqueConstraintConflict`.
  - Implemented via store-scoped sync lease (container-level), replacing per-context-only locking.

### [x] 3. Parent model passed from a different context

- Test name: `testParentObjectFromDifferentContextHandledDeterministically`
- Real-world scenario: UI-selected parent object is reused in background sync context.
- Setup:
  - Fetch/create parent in context A.
  - Call parent-scoped sync in context B using that parent instance.
- Expected behavior:
  - Deterministic handling with a clear diagnostic and a safe fallback path.
- Why DataStack helped:
  - Context-bound patterns made cross-context object usage easier to detect.
- SwiftSync status:
  - Covered by test `testParentObjectFromDifferentContextHandledDeterministically`.
  - Parent is resolved in the target sync context before mutation.
  - If the parent cannot be resolved in that context, sync aborts deterministically with a clear diagnostic and no partial writes.

### [ ] 5. Store corruption recovery

- Test name: `testStoreCorruptionRecoveryPath`
- Real-world scenario: sqlite/wal corruption after interruption or disk issue.
- Setup:
  - Initialize against a deliberately corrupted store artifact.
- Expected behavior:
  - Predictable recovery strategy (retry, reset, or explicit recoverable-state signal).
- Why DataStack helped:
  - Had remove-and-recreate logic and explicit cleanup behavior.

### [x] 6. Store erase/reset while sync is in flight

- Test name: `testResetEraseDuringInFlightSync`
- Real-world scenario: logout/account switch while background sync is active.
- Setup:
  - Start long-running sync.
  - Trigger erase/reset concurrently.
- Expected behavior:
  - Deterministic cancellation/completion path; no zombie object access.
- Why DataStack helped:
  - Coordinated reset/drop sequence reduced race windows.
- SwiftSync status:
  - Covered by test `testResetEraseDuringInFlightSync`.
  - Current behavior is deterministic completion without crash, but an in-flight update can be dropped during concurrent reset.
  - Mitigation now supported: callers can cancel in-flight sync tasks (`Task.cancel()`), and SwiftSync cooperatively stops with `SyncError.cancelled` while rolling back unsaved changes.

## P1: Consistency / UX Guarantees (Stale-Read Prevention, Last-Write Clarity)

### [x] 7. Background save visibility to main-reader context

- Test name: `testBackgroundWriteNotVisibleToMainReadWithoutRefreshPolicy`
- Real-world scenario: sync finishes, UI still shows stale values.
- Setup:
  - Main context fetches object.
  - Background context modifies and saves.
  - Main reads again without explicit refresh contract.
- Expected behavior:
  - Documented and tested visibility behavior.
  - Deterministic refresh/merge strategy.
- Why DataStack helped:
  - Explicit did-save merge path into main context.
- SwiftSync status:
  - Covered by test `testBackgroundWriteNotVisibleToMainReadWithoutRefreshPolicy`.
  - A retained object in the main context can remain stale after a background save.
  - A fresh `fetch` in the same main context observes the updated value.

### [ ] 8. User editing row while background sync updates same row

- Test name: `testRepeatedBackgroundSavesWhileUserEditsSameRow`
- Real-world scenario: edit screen open while periodic sync writes server changes.
- Setup:
  - Main context has pending local edits.
  - Background sync updates same identity repeatedly and saves.
- Expected behavior:
  - Deterministic conflict semantics (local wins, remote wins, or policy-based).
- Why DataStack helped:
  - Merge policy made conflict outcomes explicit.

## P2: Scale / Operational Confidence

### [ ] 9. Large sync batch memory pressure

- Test name: `testLongRunningBatchSyncMemoryPressureWithoutPeriodicReset`
- Real-world scenario: 50k-100k row sync on older devices.
- Setup:
  - Run very large payload in a single sync pass.
- Expected behavior:
  - Acceptable memory/time profile, or explicit batching/reset requirement.
- Why DataStack helped:
  - Disposable/non-merging contexts and reset patterns reduced memory growth.

### [ ] 10. Cross-process/store contention (app + extension)

- Test name: `testCrossProcessWriterContentionAppAndExtension`
- Real-world scenario: main app and extension write shared store concurrently.
- Setup:
  - Simulate process-like concurrent writers against shared store URL.
- Expected behavior:
  - Deterministic writer coordination and retry behavior.
- Why DataStack helped:
  - More explicit store setup and operational control surfaces.

## Execution Plan (One-by-One)

1. Start with P0 tests 1-3 (highest likelihood + easiest to reproduce).
2. Add explicit expected-policy comments in each test (pass criteria must be precise).
3. Implement the smallest mechanism required to deliver the expected deterministic outcome for each test.
4. Re-run full suite after each test/policy change.
5. Move to remaining P0 tests, then P1, then P2.

## Notes for Implementation

- Keep each new test independent and in-memory unless file-backed behavior is required.
- Prefer deterministic coordination primitives (actors, task groups, expectations) over timing sleeps.
- For each test, capture whether current behavior is:
  - production-ready and documented,
  - production-ready with guardrails,
  - needs implementation work before rollout.
