# State Capsule

## Goal

Wire the demo's task-creation flow through SwiftSync's export system so DemoSyncEngine builds a [String: Any] JSON body before "POSTing" to the fake backend, matching how a real REST client would work.

## Current status

- ✅ Done: Everything. Branch is complete and all tests green.
- 🔄 In progress: —
- ⛔ Blocked by: —

## Decisions (don't revisit)

- `@NotExport` is NOT used on `Task.id` / `Task.updatedAt` — that macro is for local-only UI state, not server-assigned fields. Instead, `DemoSyncEngine` strips `id` and `updated_at` from the export body after the fact.
- `DemoServerSimulator.createTask(body:)` is the new public entry point; the old positional-param version was renamed `createTaskInternal` (private) and is still called by `ambientCreateTask`.
- `ExportOptions(relationshipMode: .none, includeNulls: false)` — no nested relationship objects in the create body, no null noise.
- Scratch in-memory `ModelContainer` used in `DemoSyncEngine.buildCreateTaskBody` to get a persisted-enough Task object for `exportObject` to operate on.

## Constraints

- `CreateTaskSheet` / `ProjectsTabView.swift` — no changes (UI signature unchanged)
- `DemoSyncEngine.createTask(...)` public signature unchanged
- `ambientCreateTask` still calls `createTaskInternal` directly (no JSON round-trip for ambient mutations)

## Key findings

- `exportObject(using:state:)` is an instance method on Task — can be called after inserting into an in-memory context
- `state` field exports as `{"state": {"id": "todo"}}` via `@RemoteKey("state.id")` — backend parses `body["state"]["id"]`
- `stateLabel` exports as `{"state": {"label": ""}}` — backend ignores `state.label` on create

## Next steps (exact)

Nothing — work is complete. If resuming for a follow-up PR:
1. Read this file and `.agents/log.md`
2. Check `git log --oneline -5` to see what was committed

## Files touched

- `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`
- `DemoBackend/Tests/DemoBackendTests/DemoBackendTests.swift`
- `Demo/Demo/Networking/DemoAPI.swift`
- `Demo/Demo/Sync/DemoSyncEngine.swift`
