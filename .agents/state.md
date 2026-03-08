# State Capsule

## Plan
- [x] Add `SyncQueryPublisher` to-many relationship initializer test coverage.
- [x] Run targeted `SyncQueryPublisherTests` to verify green.

## Last known state
`swift test --filter testPublisherWithToManyRelationshipIDFilter` green (1 test).

## Decisions (don't revisit)
- Add coverage in tests only; no runtime or API changes.

## Files touched
- .agents/state.md
- SwiftSync/Tests/SwiftSyncTests/SyncQueryParentTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncQueryPublisherTests.swift
