# State Capsule

## Plan

- [x] Remove retry events and retry metadata from Demo error/load state models
- [x] Remove retry UI/actions from Demo screens and controllers
- [x] Update Demo docs to remove retry guidance
- [x] Re-run Demo build (`xcodebuild ... -scheme Demo ... build`) and record result

## Last known state

`xcodebuild -workspace SwiftSync.xcworkspace -scheme Demo -destination generic/platform=iOS\ Simulator build` green

## Decisions (don't revisit)

- No Earthquake Mode logic exists in `DemoBackend`; removal scope there is docs/references only.
- State machine item reordering now uses a pure data helper instead of `SwiftUI`'s `Array.move` extension.

## Files touched

- .agents/state.md
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
- Demo/Demo/Features/Debug/ShakeDetector.swift
- docs/project/local-first-freshness-flow.md
- Demo/Demo/Features/ScreenMachines.swift
- Demo/Demo/Features/TaskFormSheet.swift
- Demo/Demo/App/ErrorPresentation.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
