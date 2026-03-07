# State Capsule

## Plan
- [x] Draft project-wide monolith-friendly simplification planning doc in `docs/planning`.
- [x] Capture concrete repo-wide opportunities, non-negotiable strictness, and phased rollout open items.

## Last known state
Project-wide planning doc added at `docs/planning/monolith-friendly-simplification-pass.md`.

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
- docs/planning/monolith-friendly-simplification-pass.md
