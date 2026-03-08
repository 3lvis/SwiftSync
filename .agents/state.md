# State Capsule

## Plan

- [x] Add shared reusable Observation tracking helper and adopt it in DemoCore and Demo UIKit screen.
- [x] Tighten observation surfaces with `@ObservationIgnored` on non-observable internals.
- [x] Clarify actor isolation for `SyncQueryPublisher` and make view `@State` access control consistent.
- [x] Run relevant tests and update final state.

## Last known state

`swift test` passes (117 tests, 0 failures) with existing known macro warnings in schema-validation test macro expansions.

## Decisions (don't revisit)

- Full migration requested without backwards compatibility; remove Combine publisher-facing APIs rather than shimming.
- Keep `notificationToken` as `nonisolated(unsafe)` in `SyncQueryPublisher` to satisfy Observation macro constraints while preserving explicit observer teardown.
- In `ScreenMachines.swift`, use `_Concurrency.Task` (not bare `Task`) because the local `Task` model type shadows Swift concurrency `Task`.
- Use a single shared observation loop helper (`observeContinuously`) to avoid diverging manual `withObservationTracking` implementations.
- Keep `SyncQueryPublisher` queue contract explicit with `dispatchPrecondition(.onQueue(.main))` in `reload()` instead of forcing a global actor annotation that complicates NotificationCenter callbacks.

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
