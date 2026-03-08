# State Capsule

## Plan

- [x] Remove SwiftUI dependency from state machine data logic in `ScreenMachines.swift`
- [x] Re-run Demo app build (`xcodebuild ... -scheme Demo ... build`) and record result

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
