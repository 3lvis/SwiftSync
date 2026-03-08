# State Capsule

## Plan
- [x] Add shared Demo error primitives (`ScreenLoadState`, `ErrorPresentationState`, `presentError(_:)`) and wire root view to remove global sync banner.
- [x] Refactor project list and project detail flows to use explicit load/error states with visible retry actions.
- [x] Refactor task detail flow to use explicit load/error state with visible retry action.
- [x] Split TaskFormSheet metadata-load errors from save-submit errors with context-specific copy/actions.
- [~] Run `swift test`, perform manual Demo QA for load/retry paths, and update planning doc to keep only active follow-up items. — `swift test` passed; manual Demo QA still pending.

## Last known state
`swift test` passed; Demo error-handling refactor implemented; manual UI QA pending

## Decisions (don't revisit)
- Demo-only request: implement behavior changes without adding new Demo tests.
- Screen-level retries should be rendered in each screen UI; no global root-level sync error banner.

## Files touched
- .agents/state.md
- Demo/Demo/App/ErrorPresentation.swift
- Demo/Demo/App/DemoRootView.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Features/TaskFormSheet.swift
