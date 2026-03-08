# State Capsule

## Plan

- [x] Replace earthquake-mode empty catches with explicit stop-on-error behavior
- [x] Surface earthquake failure details in UI with dismissible alerts
- [x] Run Demo-relevant verification (`swift test`) and confirm no regressions

## Last known state

tests green (`swift test`)

## Decisions (don't revisit)

- TaskFormSheet dumb-down keeps current UX and payload semantics unchanged; this is a structural refactor only.
- Machine methods should be capability-oriented (events/mutations), not one-off forwarding wrappers.
- Earthquake mode now stops immediately on first failure and shows detailed error context in UI.

## Files touched

- .agents/state.md
- Demo/Demo/Features/ScreenMachines.swift
- Demo/Demo/Features/TaskFormSheet.swift
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
