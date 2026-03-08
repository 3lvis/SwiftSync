# State Capsule

## Plan
- [x] Draft architecture hardening plan doc from current expert assessment.

## Last known state
`docs/planning/demo-architecture-hardening-plan.md` added with non-optional hardening scope and open implementation items

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
- Demo/Demo/Features/ScreenMachines.swift
- docs/planning/demo-error-handling-plan.md
- docs/project/local-first-freshness-flow.md
- docs/planning/demo-architecture-hardening-plan.md
