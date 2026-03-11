# State Capsule

## Plan

- [x] Clean the Demo UI test sources down to the minimal maintained surface
- [x] Re-run the first Demo UI test after cleanup and record the result

## Last known state

`xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -destination 'platform=iOS Simulator,id=E8A7A5EE-68F6-4C30-952A-B75DF308E8D3' test -only-testing:DemoUITests/DemoUITests/testLaunchFetchesAndShowsSeededProjects` passed after UI test cleanup

## Decisions (don't revisit)

- Start with a docs-only planning pass before any implementation work because this task is explicitly to define the rollout
- Split the automation roadmap into a baseline pass first and edge cases second to match the requested delivery shape
- Use a deterministic UI-test-only runtime configuration so launch assertions do not depend on persisted local cache or ambient backend mutations
- Keep the UI test target focused on maintained end-to-end coverage, not generated launch screenshots or placeholder performance tests

## Files touched

- .agents/state.md
- docs/planning/demo-ui-integration-automation.md
- DemoCore/Sources/DemoCore/App/DemoRuntime.swift
- Demo/Demo/Features/Projects/ProjectsViewController.swift
- Demo/DemoUITests/DemoUITests.swift
- Demo/DemoUITests/DemoUITestsLaunchTests.swift
