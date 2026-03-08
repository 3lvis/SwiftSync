# State Capsule

## Plan
- [x] Add direct `SyncQuery` tests for plain and `predicate` overloads.
- [x] Run targeted tests to verify new coverage passes.

## Last known state
`swift test --filter SyncQueryParentTests` green (6 tests) on `feature/syncquery-overload-tests`.

## Decisions (don't revisit)
- Add coverage in tests only; no runtime or API changes.

## Files touched
- .agents/state.md
- SwiftSync/Tests/SwiftSyncTests/SyncQueryParentTests.swift
