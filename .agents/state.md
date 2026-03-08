# State Capsule

## Plan

- [x] Add Sendable payload protocol support in SwiftSync sync APIs and verify with tests.
- [x] Replace DemoCore `[String: Any]` sync payload flows with `DemoSyncPayload` DTOs.
- [x] Remove parent-object sync requirements in DemoCore by syncing via foreign-key payloads.
- [x] Flip DemoCore package to Swift 6 + strict concurrency complete and validate tests.

## Last known state

`swift test` (root) passes with 119 tests; `DemoBackend/swift test` passes; `DemoCore/swift test` passes under Swift 6 + `-strict-concurrency=complete` (with existing warning-level test closure capture diagnostics).

## Decisions (don't revisit)

- Full migration requested without backwards compatibility; remove Combine publisher-facing APIs rather than shimming.
- Keep `notificationToken` as `nonisolated(unsafe)` in `SyncQueryPublisher` to satisfy Observation macro constraints while preserving explicit observer teardown.
- In `ScreenMachines.swift`, use `_Concurrency.Task` (not bare `Task`) because the local `Task` model type shadows Swift concurrency `Task`.
- Use a single shared observation loop helper (`observeContinuously`) to avoid diverging manual `withObservationTracking` implementations.
- Keep `SyncQueryPublisher` queue contract explicit with `dispatchPrecondition(.onQueue(.main))` in `reload()` instead of forcing a global actor annotation that complicates NotificationCenter callbacks.
- User explicitly approved API-breaking concurrency refactors to maximize safety and strictness.
- Use `SyncPayloadConvertible` at SwiftSync boundaries so package consumers can keep Sendable DTOs while SwiftSync internals still work with dictionary payload semantics.

## Files touched

- .agents/state.md
- Demo/Demo/App/ContentView.swift
- Demo/Demo/DemoApp.swift
- Demo/Demo/Features/Projects/ProjectView.swift
- Demo/Demo/Features/Projects/ProjectsView.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
- Demo/Demo/Features/TaskDetail/TaskView.swift
- Demo/Demo/Features/TaskForm/TaskFormSheet.swift
- DemoCore/Sources/DemoCore/App/DemoRuntime.swift
- DemoCore/Sources/DemoCore/Features/ErrorPresentation.swift
- DemoCore/Sources/DemoCore/Features/ScreenMachines.swift
- DemoCore/Sources/DemoCore/Sync/DemoSyncEngine.swift
- SwiftSync/Sources/SwiftSync/ReactiveQuery.swift
- SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift
- SwiftSync/Tests/SwiftSyncTests/SyncQueryPublisherTests.swift
- DemoCore/Sources/DemoCore/Features/ObservationTracking.swift
- .github/workflows/ci.yml
- Demo/Demo.xcodeproj/project.pbxproj
- DemoBackend/Package.swift
- DemoCore/Package.swift
- DemoCore/Sources/DemoCore/Networking/DemoAPI.swift
- DemoCore/Sources/DemoCore/Networking/DemoSyncPayload.swift
- DemoCore/Sources/DemoCore/Models/DemoModels.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Tests/SwiftSyncTests/SyncTests.swift
- docs/project/sendable-playbook.md
