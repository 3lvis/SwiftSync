# State Capsule

## Plan

- [x] Add timestamped demo-only diagnostics around task/project sync and task detail state publication to trace when relationships become empty
- [~] Reproduce via build and inspect logs to identify the exact failure point — build passes; runtime log capture still needed
- [ ] Update the state capsule with the observed culprit and current verification state

## Last known state

DemoCore package tests pass and the Demo iOS app builds successfully with timestamped relationship diagnostics; runtime log capture still pending.

## Decisions (don't revisit)

- Treat this as demo-focused debugging first because backend payloads still contain the relationship IDs and existing SwiftSync query tests are green.

## Files touched

- .agents/state.md
- DemoCore/Sources/DemoCore/Features/ScreenMachines.swift
- DemoCore/Sources/DemoCore/Support/DemoDebugLog.swift
- DemoCore/Sources/DemoCore/Sync/DemoSyncEngine.swift
