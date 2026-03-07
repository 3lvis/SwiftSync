# State Capsule

## Plan
- [x] Add backend regression test to verify persisted item order is immediately reflected in task detail + project list payloads after reorder update.
- [x] Implement backend support for reorder-only updates (`id` + `position`) without requiring title resend.
- [x] Implement UI item drag reordering in task edit form and verify tests remain green.

## Last known state
`swift test` passes in `DemoBackend` and repo root with backend/UI item reordering support.

## Decisions (don't revisit)
- Start with backend-only scope first and defer demo app/model changes until later.
- Keep checklist item syncing in task-detail sync path first; skip list-level nested sync for now.
- Keep backend data model compatible for now; remove check/uncheck behavior from demo UX first.
- Trimmed checklist payload contract: no `done` field in responses; checklist is now list-only semantics.
- Seed data and earthquake mutation payloads should always include checklist items so demos consistently exercise nested checklist sync.
- Checklist items are list-only; backend no longer stores a `done` column.
- Renamed child resource naming from checklist/checklist_items to item/items across demo backend and demo app.
- Reordering must be for `items` naming only.

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
- docs/planning/monolith-friendly-simplification-pass.md
- DemoBackend/Sources/DemoBackend/DemoSeedData.swift
