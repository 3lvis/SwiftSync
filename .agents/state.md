# State Capsule

## Plan

- [x] Add timestamped demo-only diagnostics around task/project sync and task detail state publication to trace when relationships become empty
- [x] Reproduce via build and inspect logs to identify the exact failure point — culprit was missing user sync before task/project detail sync
- [x] Update the state capsule with the observed culprit and current verification state
- [x] Add a focused DemoCore regression test that proves `TaskDetailMachine` refreshes after a background save updates the same task
- [x] Run the relevant DemoCore tests and the demo app build, then update verification state
- [x] Add a failing SwiftSync regression test for identity-scoped reactive refresh after a background-context update
- [x] Implement a SwiftSync single-model reactive publisher and move the detail screen to it
- [x] Remove the DemoCore manual `ModelContext.didSave` workaround and rerun verification

## Last known state

SwiftSync now owns the single-row reactive refresh fix via `SyncModelPublisher`; the focused SwiftSync regression test and DemoCore tests are green after removing the redundant DemoCore stale-detail test, and the earlier Demo iOS app build is green.

## Decisions (don't revisit)

- Treat this as demo-focused debugging first because backend payloads still contain the relationship IDs and existing SwiftSync query tests are green.
- The culprit was demo sync ordering, not payload shape or SwiftSync query filtering: task payloads were being applied with `userRowsBeforeSync=0`, so user-backed relationships could never resolve.
- The stale assignee-after-save bug is currently fixed in DemoCore by refreshing the current task snapshot from `mainContext` after background-context saves for the same container; add a regression test before moving this behavior lower.
- The proper permanent fix belongs in SwiftSync as an identity-scoped reactive API rather than per-screen `didSave` observation.
- `SyncModelPublisher` is the non-SwiftUI counterpart to the existing `@SyncModel` wrapper and is now the preferred way for state machines to observe a single row by identity.
- The DemoCore stale-detail regression test became redundant once the fix and regression coverage moved into SwiftSync; keep DemoCore verification at build level for that path.

## Files touched

- .agents/state.md
- DemoCore/Sources/DemoCore/Features/ScreenMachines.swift
- DemoCore/Sources/DemoCore/Support/DemoDebugLog.swift
- DemoCore/Sources/DemoCore/Sync/DemoSyncEngine.swift
- DemoCore/Tests/DemoCoreTests/DirtyTrackingGapTests.swift
- SwiftSync/Sources/SwiftSync/ReactiveQuery.swift
- SwiftSync/Sources/SwiftSync/SyncModelPublisher.swift
- SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift
- SwiftSync/Tests/SwiftSyncTests/SyncQueryPublisherTests.swift
