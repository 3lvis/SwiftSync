# State Capsule

## Plan
- [x] Create feature branch and initialize restart-safe state tracking
- [x] Add failing tests for Earthquake Mode stress-runner core behavior (finite session, cancellable, opt-in)
- [x] Implement debug stress-runner orchestration in `DemoSyncEngine`
- [x] Remove default polling loops from `ProjectDetailView` and `TaskDetailView` while keeping initial load and pull-to-refresh
- [x] Add DEBUG-only shake trigger + confirmation prompt + running indicator + stop control on active detail screens
- [x] Run targeted tests, then update planning doc and state capsule with final status
- [x] Move Earthquake action controls to floating bottom placement in detail screens
- [x] Expand task-detail stress mutation coverage to assignee + reviewers + watchers (not just scalar fields)
- [x] Rebuild Demo iOS scheme and validate compile status

## Last known state
`swift test --filter FiniteAsyncRunnerTests` and full `swift test` are green; Demo rebuild after follow-up fixes also succeeded via `xcodebuild -workspace SwiftSync.xcworkspace -scheme Demo -destination 'generic/platform=iOS Simulator' build`.

## Decisions (don't revisit)
- Scope Earthquake Mode to active detail screens (`ProjectDetailView` and `TaskDetailView`) to keep blast radius explicit.
- Implement a finite stress session with deterministic caps (time/iteration) and explicit stop.
- Keep production behavior unchanged unless debug stress mode is explicitly activated.

## Files touched
- `.agents/state.md`
- `SwiftSync/Sources/SwiftSync/FiniteAsyncRunner.swift`
- `SwiftSync/Tests/SwiftSyncTests/FiniteAsyncRunnerTests.swift`
- `Demo/Demo/Sync/DemoSyncEngine.swift`
- `Demo/Demo/Features/Projects/ProjectsTabView.swift`
- `Demo/Demo/Features/TaskDetail/TaskDetailView.swift`
- `Demo/Demo/Features/Debug/ShakeDetector.swift`
