# State Capsule

## Plan

- [x] Replace Combine-based observable models with Observation in SwiftSync and DemoCore.
- [x] Refactor demo SwiftUI and UIKit surfaces to consume Observation state.
- [x] Update tests for removed Combine APIs and verify behavior.
- [x] Run relevant test suite and capture final state.

## Last known state

`swift test` passes and `xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -configuration Debug -destination "generic/platform=iOS Simulator" build` succeeds after method cleanup.

## Decisions (don't revisit)

- Full migration requested without backwards compatibility; remove Combine publisher-facing APIs rather than shimming.
- Keep `notificationToken` as `nonisolated(unsafe)` in `SyncQueryPublisher` to satisfy Observation macro constraints while preserving explicit observer teardown.
- In `ScreenMachines.swift`, use `_Concurrency.Task` (not bare `Task`) because the local `Task` model type shadows Swift concurrency `Task`.

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
