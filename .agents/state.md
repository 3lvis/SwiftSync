# State Capsule

## Plan
- [x] Replace scattered screen/load state mutations with centralized state machines and reducer-driven transitions.
- [x] Refactor project list/detail and task detail to dispatch events into machines instead of directly assigning UI state.
- [x] Refactor TaskFormSheet metadata/save flows to machine-managed state and machine-driven UI outputs.
- [x] Run `swift test` and update planning/state docs to reflect remaining follow-up work.

## Last known state
naming/structure polish complete across the four target screens; `swift test` passing; manual Demo UI QA still pending

## Decisions (don't revisit)
- Demo-only request: implement behavior changes without adding new Demo tests.
- Screen-level retries should be rendered in each screen UI; no global root-level sync error banner.
- Real state machine means reducers own transitions; views/controllers send events and render state.
- Keep screen wiring uniform: each screen dispatches load events via a single `requestLoad`/`requestMetadataLoad` helper and renders from machine state only.

## Files touched
- .agents/state.md
- Demo/Demo/App/ErrorPresentation.swift
- Demo/Demo/App/DemoRootView.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Features/TaskFormSheet.swift
- docs/planning/demo-error-handling-plan.md
- docs/project/local-first-freshness-flow.md
