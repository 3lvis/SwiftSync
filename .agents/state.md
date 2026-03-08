# State Capsule

## Plan
- [x] Move project list/detail/task detail to feature machines that own both data observation and load state.
- [x] Move TaskForm metadata + submit orchestration into a single feature machine and keep view as render + event dispatch.
- [x] Build Demo app and run `swift test`, then update state capsule with final status.

## Last known state
machine-first refactor complete for the four target screens; `xcodebuild` and `swift test` both passing

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
