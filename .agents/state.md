# State Capsule

## Plan
- [x] Add createdAt to all 5 models in DemoModels.swift
- [x] Add createdAt to SeedProject/SeedUser/SeedTask + update generate()
- [x] Update DB schema + read payloads + createTaskInternal + createTask(body:) + ambientCreateTask + seed inserts
- [x] Update buildCreateTaskBody in DemoSyncEngine
- [x] Update tests
- [x] Run DemoBackendTests + SwiftSync suite + Demo build

## Last known state
10/10 DemoBackendTests green / Demo BUILD SUCCEEDED

## Decisions (don't revisit)
- Client is authority for id, created_at, updated_at on CREATE only — PATCH endpoints still own updated_at server-side
- created_at added to all 5 models (Project, User, TaskStateOption, UserRoleOption, Task)
- TaskStateOption and UserRoleOption created_at is hardcoded epoch 0 constant in payload (not stored in DB)
- Duplicate id on createTask(body:) → validation error, no silent upsert
- recoverOnFailure handles SwiftData migration — no VersionedSchema needed for demo
- nextTaskID() deleted entirely — id always comes from body dict or ambientCreateTask (UUID().uuidString)
- Seed createdAt = updatedAt for every entity

## Files touched
- `Demo/Demo/Models/DemoModels.swift`
- `DemoBackend/Sources/DemoBackend/DemoSeedData.swift`
- `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`
- `Demo/Demo/Sync/DemoSyncEngine.swift`
- `DemoBackend/Tests/DemoBackendTests/DemoBackendTests.swift`
