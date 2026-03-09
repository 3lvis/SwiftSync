# State Capsule

## Plan

- [x] Add animation triggers for reactive list changes in `TaskView` and `TaskFormSheet`
- [x] Build the demo app after the UI changes and record the result

## Last known state

added animation bindings in `TaskView` and `TaskFormSheet`; `xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -configuration Debug -destination 'generic/platform=iOS Simulator' build` succeeded after simplifying `TaskView`

## Decisions (don't revisit)

- Keep the fix in `Demo/Demo/**` rather than changing shared query infrastructure because the reported issue is a demo view presentation problem.
- Update the written policy instead of running a build now because the request is to change repo rules, not to verify a specific app change.
- Build the demo app now because the user explicitly requested it and the updated policy requires that verification path for demo changes.

## Files touched

- .agents/state.md
- AGENTS.md
