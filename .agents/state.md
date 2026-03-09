# State Capsule

## Plan

- [x] Review nested to-many dirty-tracking implementation points and existing coverage.
- [x] Add failing library tests for nested to-many dirty-marking behavior.
- [x] Update nested to-many sync to mark owners dirty on membership changes and clears, sharing logic with the foreign-key path.
- [x] Update dirty-tracking docs to match the implemented to-many coverage.
- [x] Run targeted SwiftSync tests to verify the change set.

## Last known state

targeted SwiftSync tests green: SyncMarkChangedCallSiteTests and RelationshipIntegrityRegressionTests passed after nested to-many dirty-marking fix and docs update

## Decisions (don't revisit)

- This task only implements the active items from `docs/planning/nested-to-many-dirty-tracking-gap.md`.
- Strict TDD applies because the behavior change is in `SwiftSync/**`.
- Touching `SwiftSync/Sources/SwiftSync/Core.swift` means iOS regression will run on merge.

## Files touched

- .agents/state.md
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Tests/SwiftSyncTests/SyncRelationshipIntegrityTests.swift
- docs/project/ios-dirty-tracking-gap.md
- docs/planning/nested-to-many-dirty-tracking-gap.md
