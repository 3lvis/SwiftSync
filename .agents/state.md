# State Capsule

## Plan

### Track 1 — API Surface Reduction (`docs/planning/api-surface-reduction.md`)

- [x] Remove `SyncQueryPublisher` predicate and `relatedTo:through:` inits — **REVERTED, decided: keep**
  - Removal was done then reverted: parity with `@SyncQuery` query shapes is the design contract
  - Decision recorded in `docs/planning/api-surface-reduction.md` Decisions table — do not revisit
- [x] Remove `protocol SyncRelationshipSchemaIntrospectable` from `Core.swift`
  - Dead protocol — no conformances, no callers, requirement already on `SyncModelable`
  - 7 lines deleted; all 112 XCTest + 30 Swift Testing tests green

### Track 2 — Draft Model Pattern (`docs/planning/demo-draft-model-export.md`)

- [ ] Targeted test: verify `exportObject` is safe on uninserted `@Model`
- [ ] Add `draft()` generation to `@Syncable` macro
- [ ] Add `draft()` to `SyncUpdatableModel` protocol (or macro-only)
- [ ] Refactor demo update call sites — `draft()` + `exportObject(for:)`, remove dict surgery
- [ ] Run full build and test suite

## Last known state
All tests green. XCTest: 112 passed. Swift Testing: 30 passed. Branch: remove-sqp-predicate-relatedto-inits.

## Decisions
- `required` on `SyncPayload` must stay public — macro-generated conformances call it.
- `syncApplyToX` family must stay public — macro expansion calls them in client module scope.
- `package` access level: deferred — no SPM solution yet.
- `SyncQueryPublisher` predicate + `relatedTo:through:` inits: keep — parity with `@SyncQuery` is the contract, not demo coverage.

## Files touched (open work)
- `SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift`
- `SwiftSync/Tests/SwiftSyncTests/SyncQueryPublisherTests.swift`
- `SwiftSync/Sources/SwiftSync/SyncableMacro.swift`
- `SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift`
- `SwiftSync/Sources/SwiftSync/Core.swift`
- Demo update call sites (`TaskDetailView`, `EditTaskDescriptionSheet`, `AssigneePickerSheet`)
