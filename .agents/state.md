# State Capsule

## Plan

- [x] Create feature branch for DemoCore extraction.
- [x] Add `DemoCore`/`DemoCoreTests` SwiftPM targets and initial source layout.
- [x] Move demo models, networking, sync engine, runtime, reducers, and machines into `DemoCore` with public APIs.
- [x] Update Demo app UI files to import/use `DemoCore` types only.
- [x] Link `Demo` Xcode target against `DemoCore` and remove direct dependencies on moved files.
- [x] Remove `DemoTests` target and replace with `DemoCoreTests` unit coverage for non-UI logic.
- [x] Update `docs/planning/demo-architecture-hardening-plan.md` open items to reflect the new architecture direction.
- [x] Run `swift test` and fix any compile/test issues.

## Last known state

`swift test` passes (119 tests). DemoCore target compiles with Swift 5 language mode to preserve existing Demo concurrency behavior.

## Decisions (don't revisit)

- Keep `Demo` app UI-only; all testable non-UI logic belongs in `DemoCore`.
- Do not add demo app unit tests or integration UI tests in this change.
- Update `@Syncable` macro generation to emit public protocol members for public models.
- Use Swift 5 language mode for `DemoCore` target to avoid Swift 6 `sending` diagnostics for existing demo machine/task patterns.

## Files touched

- .agents/state.md
- Package.swift
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- SwiftSync/Tests/SwiftSyncMacrosTests/SyncableMacroDiagnosticsTests.swift
- DemoCore/Sources/DemoCore/Models/DemoModels.swift
- DemoCore/Sources/DemoCore/Networking/DemoAPI.swift
- DemoCore/Sources/DemoCore/Sync/DemoSyncEngine.swift
- DemoCore/Sources/DemoCore/App/DemoRuntime.swift
- DemoCore/Sources/DemoCore/Features/ErrorPresentation.swift
- DemoCore/Sources/DemoCore/Features/ScreenMachines.swift
- DemoCore/Tests/DemoCoreTests/DirtyTrackingGapTests.swift
- Demo/Demo/Features/TaskFormSheet.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
- Demo/Demo/App/DemoRootView.swift
- Demo/Demo/DemoApp.swift
- Demo/Demo.xcodeproj/project.pbxproj
- docs/planning/demo-architecture-hardening-plan.md
