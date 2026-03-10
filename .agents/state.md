# State Capsule

## Plan

- [x] Add timestamped demo-only diagnostics around task/project sync and task detail state publication to trace when relationships become empty
- [x] Reproduce via build and inspect logs to identify the exact failure point — culprit was missing user sync before task/project detail sync
- [~] Update the state capsule with the observed culprit and current verification state — code fix applied; runtime confirmation still pending

## Last known state

DemoCore package tests pass and the Demo iOS app builds successfully after syncing users before task list/detail payload application; runtime confirmation still pending.

## Decisions (don't revisit)

- Treat this as demo-focused debugging first because backend payloads still contain the relationship IDs and existing SwiftSync query tests are green.
- The culprit was demo sync ordering, not payload shape or SwiftSync query filtering: task payloads were being applied with `userRowsBeforeSync=0`, so user-backed relationships could never resolve.

## Files touched

- .agents/state.md
- DemoCore/Sources/DemoCore/Features/ScreenMachines.swift
- DemoCore/Sources/DemoCore/Support/DemoDebugLog.swift
- DemoCore/Sources/DemoCore/Sync/DemoSyncEngine.swift
