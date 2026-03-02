# State Capsule

## Plan
- [x] Create branch `fix/sync-mark-changed-dirty-tracking` from main
- [x] Rewrite doc as hypothesis/plan (remove "Fixed" status, add investigation steps)
- [x] Write red test — spy-based: OneSidedTask.syncMarkChanged() counter, assert count=1 after membership change
- [x] Run test and confirm it fails for the expected reason (count is 0, syncMarkChanged not yet called)
- [x] Confirm "no spurious calls" test passes green (correct even without the fix)
- [x] Document why notification-based persistent-store test doesn't work on macOS
- [ ] (future) Implement syncMarkChanged() fix
- [ ] (future) Confirm red test turns green after fix

## Last known state
testSyncApplyToManyForeignKeysCallsSyncMarkChangedAfterMembershipChange: RED (count 0, expected 1)
testSyncApplyToManyForeignKeysDoesNotCallSyncMarkChangedWhenUnchanged: green

## Decisions (don't revisit)
- Notification-based test (persistent store → changedIDs) does NOT work: macOS CoreData always surfaces the owner even without a scalar write. The gap is iOS-only and cannot be driven red via swift test on macOS.
- Spy-based test is the correct approach: OneSidedTask.syncMarkChanged() increments a static counter; tests assert the count. Platform-independent, drives red without the fix.
- Test models use hand-written SyncUpdatableModel (no @Syncable) so no macro can accidentally write a scalar and mask the gap.
- syncMarkChanged() is declared directly on OneSidedTask (not on the protocol yet) so the spy works even before the fix adds it to SyncUpdatableModel.

## Files touched
- docs/planning/sync-mark-changed-dirty-tracking.md
- .agents/state.md
- SwiftSync/Tests/SwiftSyncTests/SyncRelationshipIntegrityTests.swift (pending)
