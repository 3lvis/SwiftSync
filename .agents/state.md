# State Capsule

## Plan

- [x] Replace duplicated Observation observer plumbing with actor-isolated observer implementations and tighter observation surfaces.
- [x] Move package/app compiler settings toward stricter concurrency defaults, keeping DemoCore on Swift 5 mode pending Sendable payload boundary work.
- [x] Add CI coverage for all local packages plus a Sendable/concurrency playbook doc.
- [x] Run full relevant test suites and update final state.

## Last known state

`swift test` (root) passes; `DemoBackend/swift test` passes; `DemoCore/swift test` passes.

## Decisions (don't revisit)

- Full migration requested without backwards compatibility; remove Combine publisher-facing APIs rather than shimming.
- Keep `notificationToken` as `nonisolated(unsafe)` in `SyncQueryPublisher` to satisfy Observation macro constraints while preserving explicit observer teardown.
- In `ScreenMachines.swift`, use `_Concurrency.Task` (not bare `Task`) because the local `Task` model type shadows Swift concurrency `Task`.
- Use a single shared observation loop helper (`observeContinuously`) to avoid diverging manual `withObservationTracking` implementations.
- Keep `SyncQueryPublisher` queue contract explicit with `dispatchPrecondition(.onQueue(.main))` in `reload()` instead of forcing a global actor annotation that complicates NotificationCenter callbacks.
- User explicitly approved API-breaking concurrency refactors to maximize safety and strictness.
- Full Swift 6 + strict concurrency migration is blocked in DemoCore by non-Sendable `[String: Any]` payload boundaries to `SyncContainer`; keep DemoCore in Swift 5 mode until payload DTO migration.

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
- docs/project/sendable-playbook.md
