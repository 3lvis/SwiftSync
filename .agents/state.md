# State Capsule

## Plan

- [x] Remove the pre-confirmation destructive swipe behavior from project task deletion
- [x] Build the demo app after the swipe-action change and record the result

## Last known state

verified that actual task deletion only happens from the alert confirm button; changed the swipe action to a non-destructive button with red tint, and `xcodebuild -project Demo/Demo.xcodeproj -scheme Demo -configuration Debug -destination 'generic/platform=iOS Simulator' build` succeeded

## Decisions (don't revisit)

- Keep the fix in `Demo/Demo/**` rather than changing shared query infrastructure because the reported issue is a demo view presentation problem.
- Update the written policy instead of running a build now because the request is to change repo rules, not to verify a specific app change.
- Build the demo app now because the user explicitly requested it and the updated policy requires that verification path for demo changes.
- Keep the swipe button visually destructive but not semantically destructive so the confirmation alert can appear without the row pre-animating away.

## Files touched

- .agents/state.md
- AGENTS.md
