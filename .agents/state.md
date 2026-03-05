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
- [x] Define Step 2 freshness architecture using engine-centric naming (`DataKey`, `LoadDecision`)
- [x] Add failing SwiftSync tests for freshness evaluator contracts (empty/fresh/stale)
- [x] Implement reusable freshness evaluator primitives in SwiftSync
- [x] Wire DemoSyncEngine freshness metadata (TTL + per-key timestamps + has-local probes)
- [x] Run tests/build and update planning doc/status for Step 2 progress
- [x] Implement Step 3 scope-level status stream (`phase` + `path` + `error`) with deterministic transitions
- [x] Add Step 3 ordering tests in SwiftSync for status transition reducer
- [x] Implement Step 4 local-first orchestration entry points and migrate screens/forms to use them
- [x] Complete remaining Step 1/2/3/4 validation checks that are automatable from CLI
- [x] Implement Step 5 docs pass: local-first flow, Earthquake boundaries, what-this-teaches, troubleshooting
- [x] Run full verification (`swift test`, Demo build) and finalize planning checklist
- [x] Align planning docs to single-call-per-screen direction (no caller reason, no compatibility surface)
- [ ] Refactor engine/view API to enforce one public load call per screen flow
- [ ] Remove obsolete split orchestration methods and update verification

## Last known state
Planning doc has been rewritten to current direction; implementation still needs single-call-per-screen cleanup.

## Decisions (don't revisit)
- Scope Earthquake Mode to active detail screens (`ProjectDetailView` and `TaskDetailView`) to keep blast radius explicit.
- Implement a finite stress session with deterministic caps (time/iteration) and explicit stop.
- Keep production behavior unchanged unless debug stress mode is explicitly activated.
- Keep freshness orchestration complexity in `DemoSyncEngine`; expose only lightweight reusable primitives from SwiftSync.
- Keep explicit network `sync*` APIs intact; add local-first `load*` orchestration APIs beside them.
- Public orchestration must not expose load-path hints (no public `reason` parameter).

## Files touched
- `.agents/state.md`
- `SwiftSync/Sources/SwiftSync/FiniteAsyncRunner.swift`
- `SwiftSync/Tests/SwiftSyncTests/FiniteAsyncRunnerTests.swift`
- `Demo/Demo/Sync/DemoSyncEngine.swift`
- `Demo/Demo/Features/Projects/ProjectsTabView.swift`
- `Demo/Demo/Features/TaskDetail/TaskDetailView.swift`
- `Demo/Demo/Features/Debug/ShakeDetector.swift`
- `SwiftSync/Sources/SwiftSync/DataFreshnessPolicy.swift`
- `SwiftSync/Sources/SwiftSync/ScopeSyncStatus.swift`
- `SwiftSync/Tests/SwiftSyncTests/DataFreshnessTests.swift`
- `SwiftSync/Tests/SwiftSyncTests/ScopeSyncStatusReducerTests.swift`
- `Demo/Demo/Features/Projects/ProjectsViewController.swift`
- `Demo/Demo/Features/TaskFormSheet.swift`
- `docs/planning/engine-local-first-freshness-flow.md`
- `docs/project/local-first-freshness-flow.md`
