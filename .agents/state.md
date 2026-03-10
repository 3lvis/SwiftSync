# State Capsule

## Plan

- [x] Add DemoCore tests for machine-owned render state across all machine-backed screens
- [x] Refactor DemoCore machines to expose explicit render state for list, detail, and form metadata screens
- [x] Refine `TaskFormSheet` into explicit screen/form/content layers with named lifecycle hooks
- [x] Re-run DemoCore tests and build the Demo scheme

## Last known state

TaskFormSheet layering complete; DemoCore tests green and Demo build succeeded

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
