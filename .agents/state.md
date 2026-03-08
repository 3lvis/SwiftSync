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
- [x] Restructure Demo UI file layout from first principles (screen-driven boundaries, no tab naming).
- [x] Rename Projects files (`ProjectsTabView`/`ProjectsViewController`) to screen/list naming.
- [x] Extract UIKit representable and project detail screen out of projects root screen file.
- [x] Split `TaskFormSheet` into container + sections/helpers files with no behavior changes.
- [x] Rename `TaskDetailView` to `TaskDetailScreen` and keep references consistent.
- [x] Add app navigation wrapper and keep scenario picker in app shell.
- [x] Run `swift test` after UI refactor and update state.
- [x] Rename Demo UI type/file names to remove `Screen`/`List` suffixes.
- [x] Rename app shell and section/support file names (`DemoRootView`, `AppNavigationView`, `*Sections`, `*Helpers`).

## Last known state

`swift test` passes (117 tests). `xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -destination "generic/platform=iOS Simulator" build` succeeds.

## Decisions (don't revisit)

- Keep `Demo` app UI-only; all testable non-UI logic belongs in `DemoCore`.
- Do not add demo app unit tests or integration UI tests in this change.
- Update `@Syncable` macro generation to emit public protocol members for public models.
- Use Swift 5 language mode for `DemoCore` target to avoid Swift 6 `sending` diagnostics for existing demo machine/task patterns.
- Wire `DemoCore` as its own local package (`../DemoCore`) in the Demo Xcode project, matching `DemoBackend` wiring style.
- Keep project list implementation in UIKit while refactoring file structure.

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
- DemoCore/Package.swift
- Demo/Demo/App/AppNavigationView.swift
- Demo/Demo/Features/Projects/ProjectsScreen.swift
- Demo/Demo/Features/Projects/ProjectsListRepresentable.swift
- Demo/Demo/Features/Projects/ProjectDetailScreen.swift
- Demo/Demo/Features/Projects/ProjectsListViewController.swift
- Demo/Demo/Features/TaskDetail/TaskDetailScreen.swift
- Demo/Demo/Features/TaskDetail/TaskDetailSections.swift
- Demo/Demo/Features/TaskForm/TaskFormSheet.swift
- Demo/Demo/Features/TaskForm/TaskFormSections.swift
- Demo/Demo/Features/TaskForm/TaskFormHelpers.swift
- Demo/Demo/App/DemoView.swift
- Demo/Demo/App/DemoFlowView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailContent.swift
- Demo/Demo/Features/TaskForm/TaskFormContent.swift
- Demo/Demo/Features/TaskForm/TaskFormSupport.swift
