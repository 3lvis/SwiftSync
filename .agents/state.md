# State Capsule

## Plan

- [x] Add machine-level task delete failure state with retry flow in project detail
- [x] Remove redundant rethrow catch blocks that add no behavior
- [x] Run Demo-relevant verification (`swift test`) and confirm no regressions

## Last known state

tests green (`swift test`)

## Decisions (don't revisit)

- TaskFormSheet dumb-down keeps current UX and payload semantics unchanged; this is a structural refactor only.
- Machine methods should be capability-oriented (events/mutations), not one-off forwarding wrappers.

## Files touched

- .agents/state.md
- Demo/Demo/Features/ScreenMachines.swift
- Demo/Demo/Features/TaskFormSheet.swift
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
