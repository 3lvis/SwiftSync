# State Capsule

## Plan

- [x] Move the UI automation journey plan into `DemoUITests.swift` as the source of truth
- [x] Reduce the planning doc to a pointer so it does not compete with the test file
- [x] Re-run the relevant UI tests and update `.agents/state.md`

## Last known state

`xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,id=E8A7A5EE-68F6-4C30-952A-B75DF308E8D3' test -only-testing:DemoUITests/DemoUITests/testLaunchFetchesAndShowsSeededProjects -only-testing:DemoUITests/DemoUITests/testProjectAndTaskDetailShowSeededContent` passed after moving the roadmap into `DemoUITests.swift`

## Decisions (don't revisit)

- Start with a docs-only planning pass before any implementation work because this task is explicitly to define the rollout
- Split the automation roadmap into a baseline pass first and edge cases second to match the requested delivery shape
- Use a deterministic UI-test-only runtime configuration so launch assertions do not depend on persisted local cache or ambient backend mutations
- Keep the UI test target focused on maintained end-to-end coverage, not generated launch screenshots or placeholder performance tests
- The planning doc should be anchored to the seeded canonical demo data and actual screen states, not generic CRUD wording
- Making the Demo app intentionally easy to automate is in scope, including runtime and backend reshaping for deterministic UI states
- Build harness pieces only when a concrete UI flow needs them; avoid speculative test infrastructure
- The next planning layer should be user journeys, not screen permutations
- UI tests should map to user goals, not checkpoints like "screen opened successfully"
- `DemoUITests.swift` should be the active planning source for UI automation journeys

## Files touched

- .agents/state.md
- docs/planning/demo-ui-integration-automation.md
- DemoCore/Sources/DemoCore/App/DemoRuntime.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
- Demo/DemoUITests/DemoUITests.swift
- Demo/DemoUITests/DemoUITestsLaunchTests.swift
- docs/planning/demo-ui-integration-automation.md
- Demo/Demo/Features/Projects/ProjectView.swift
- Demo/Demo/Features/TaskDetail/TaskView.swift
