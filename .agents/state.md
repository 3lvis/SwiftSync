# State Capsule

## Plan

- [x] Add DemoCore tests for machine-owned render state across all machine-backed screens
- [x] Refactor DemoCore machines to expose explicit render state for list, detail, and form metadata screens
- [x] Merge `TaskFormSheet` body with the form shell and move save-failure presentation into a dedicated view modifier
- [x] Re-run the Demo scheme build

## Last known state

TaskFormSheet body merged with form shell; save-failure presentation extracted; Demo build succeeded

## Decisions (don't revisit)

- This task now includes `DemoCore/**`, so strict TDD applies for the machine state refactor

## Files touched

- .agents/state.md
- Demo/Demo/Features/Projects/ProjectView.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
- Demo/Demo/Features/TaskForm/TaskFormSheet.swift
- Demo/Demo/Features/TaskDetail/TaskView.swift
- DemoCore/Sources/DemoCore/Features/ScreenMachines.swift
- DemoCore/Tests/DemoCoreTests/ScreenStateResolutionTests.swift
