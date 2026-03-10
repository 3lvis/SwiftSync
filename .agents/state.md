# State Capsule

## Plan

- [x] Identify logging added across demo and library targets and confirm the intended removals
- [x] Remove the targeted logging while preserving behavior
- [x] Run relevant verification for touched library/demo code and record the result

## Last known state

`swift test` passed on 2026-03-10.

## Decisions (don't revisit)

- Work is happening on `chore/remove-demo-library-logging` because implementation must not happen on `main`.

## Files touched

- .agents/state.md
- DemoCore/Sources/DemoCore/Features/ScreenMachines.swift
- DemoCore/Sources/DemoCore/Support/DemoDebugLog.swift
- DemoCore/Sources/DemoCore/Sync/DemoSyncEngine.swift
