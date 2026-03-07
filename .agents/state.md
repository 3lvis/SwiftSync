# State Capsule

## Plan
- [x] Add failing backend regression tests for dropping checklist `done` input/storage.
- [x] Remove checklist `done` column/handling from backend schema and inserts.
- [x] Run DemoBackend and root package tests to confirm green.

## Last known state
`swift test` passed in `DemoBackend` and repository root package after removing checklist `done` storage.

## Decisions (don't revisit)
- Start with backend-only scope first and defer demo app/model changes until later.
- Keep checklist item syncing in task-detail sync path first; skip list-level nested sync for now.
- Keep backend data model compatible for now; remove check/uncheck behavior from demo UX first.
- Trimmed checklist payload contract: no `done` field in responses; checklist is now list-only semantics.
- Seed data and earthquake mutation payloads should always include checklist items so demos consistently exercise nested checklist sync.
- Checklist items are list-only; backend no longer stores a `done` column.

## Files touched
- .agents/state.md
- DemoBackend/Tests/DemoBackendTests/DemoBackendTests.swift
- DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift
- Demo/Demo/Models/DemoModels.swift
- Demo/Demo/App/DemoRuntime.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
- Demo/Demo/Features/TaskFormSheet.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Features/Projects/ProjectsTabView.swift
