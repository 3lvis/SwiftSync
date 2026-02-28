# State Capsule

## Plan
- [x] Write failing tests for DemoServerSimulator.createTask(body:)
- [x] Implement DemoServerSimulator.createTask(body:) + rename internal method
- [x] Update FakeDemoAPIClient.createTask to accept body dict
- [x] Update DemoSyncEngine.createTask to build body via export
- [x] Update existing createTask test to use new body: signature
- [x] Run DemoBackendTests + SwiftSync test suite

## Last known state
tests green / build succeeded

## Decisions (don't revisit)
- `@NotExport` not used on `Task.id`/`updatedAt` — that macro is for local-only UI state, not server-assigned fields; strip them from the export body in DemoSyncEngine instead
- `createTaskInternal` kept private for ambient mutations — no reason to route internal backend mutations through JSON
- `ExportOptions(relationshipMode: .none, includeNulls: false)` — keeps the create body clean; no nil noise, no nested relationship objects
- Scratch in-memory `ModelContainer` used in `buildCreateTaskBody` — gives exportObject a properly inserted model to operate on

## Files touched
- `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`
- `DemoBackend/Tests/DemoBackendTests/DemoBackendTests.swift`
- `Demo/Demo/Networking/DemoAPI.swift`
- `Demo/Demo/Sync/DemoSyncEngine.swift`
