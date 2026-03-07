# State Capsule

## Plan
- [x] Remove temporary item-order diagnostics once backend persistence was confirmed.
- [x] Commit reorder support checkpoint and branch for task-detail stale-order fix.
- [x] Fix task detail item rendering to observe `Item` rows directly via `@SyncQuery` scoped by `taskID`.
- [x] Re-run DemoBackend tests, root package tests, and Demo app build.
- [x] Clean up cross-context warning by removing duplicate `Item` insertion in task form.

## Last known state
Demo app builds after removing duplicate `editContext.insert(item)` in task form; cross-context insert warning path eliminated.

## Decisions (don't revisit)
- Start with backend-only scope first and defer demo app/model changes until later.
- Keep item syncing in task-detail sync path first; skip list-level nested sync for now.
- Keep backend data model compatible for now; remove check/uncheck behavior from demo UX first.
- Trimmed item payload contract: no `done` field in responses; items are now list-only semantics.
- Seed data and earthquake mutation payloads should always include items so demos consistently exercise nested item sync.
- Items are list-only; backend no longer stores a `done` column.
- Renamed child resource naming to item/items across demo backend and demo app.
- Reordering must be for `items` naming only.
- Task detail should read ordered `items` from a direct `@SyncQuery` instead of relying on potentially stale `task.items` relationship snapshots.
- New `Item(task: draft)` should rely on relationship ownership in the same context; do not explicitly re-insert into `editContext`.

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
