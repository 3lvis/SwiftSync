# State Capsule

## Plan

### Track 1 — API Surface Reduction (`docs/planning/api-surface-reduction.md`)

- [x] Remove `SyncQueryPublisher` predicate and `relatedTo:through:` inits
  - Deleted tests first, then removed the 3 inits; `predicate`/`postFetchFilter` private state also removed
  - `init(_:predicate:in:sortBy:)`, `init(_:relatedTo:relatedID:through:in:sortBy:)` ×2

### Track 2 — Draft Model Pattern (`docs/planning/demo-draft-model-export.md`)

- [ ] Targeted test: verify `exportObject` is safe on uninserted `@Model`
- [ ] Add `draft()` generation to `@Syncable` macro
- [ ] Add `draft()` to `SyncUpdatableModel` protocol (or macro-only)
- [ ] Refactor demo update call sites — `draft()` + `exportObject(for:)`, remove dict surgery
- [ ] Run full build and test suite

## Last known state
All tests green. XCTest: 109 passed. Swift Testing: 30 passed.

## Decisions
- `required` on `SyncPayload` must stay public — macro-generated conformances call it.
- `syncApplyToX` family must stay public — macro expansion calls them in client module scope.
- `package` access level: deferred — no SPM solution yet.

## Files touched (open work)
- `SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift`
- `SwiftSync/Tests/SwiftSyncTests/SyncQueryPublisherTests.swift`
- `SwiftSync/Sources/SwiftSync/SyncableMacro.swift`
- `SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift`
- `SwiftSync/Sources/SwiftSync/Core.swift`
- Demo update call sites (`TaskDetailView`, `EditTaskDescriptionSheet`, `AssigneePickerSheet`)
