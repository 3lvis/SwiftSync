# State Capsule

## Plan
- [x] Write failing tests that pin UUID format expectations
- [x] Replace seed IDs in DemoSeedData.generate() with stable UUID constants
- [x] Replace nextTaskID() with UUID generation in DemoServerSimulator
- [x] Remove "user-1" hardcoded fallbacks in SeedTask.init and ambientCreateTask
- [x] Update smallSeedData() in tests to use UUID constants
- [x] Update test assertions that compare against "task-1", "project-1", "user-1" literals
- [x] Run DemoBackendTests + SwiftSync suite + Demo build

## Last known state
10/10 DemoBackendTests green / Demo BUILD SUCCEEDED

## Decisions (don't revisit)
- Seed IDs use stable UUID constants in DemoSeedData.SeedIDs — not random, deterministic across installs
- State IDs ("todo", "inProgress", "done") unchanged — enum-like values, not entity IDs
- SeedTask.init "user-1" fallback replaced with task's own id — no magic string fallback
- ambientCreateTask "user-1" fallback replaced with userIDs.first! (array already guarded non-empty)
- nextTaskID() now returns UUID().uuidString — SUBSTR/LIKE 'task-%' SQL entirely removed

## Files touched
- `DemoBackend/Sources/DemoBackend/DemoSeedData.swift`
- `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`
- `DemoBackend/Tests/DemoBackendTests/DemoBackendTests.swift`
