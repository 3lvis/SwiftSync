# State Capsule

## Plan
- [x] Update tests/call sites to `relationship:` + `relationshipID:` names.
- [x] Run targeted tests to confirm expected compile failures before API rename.
- [x] Rename SyncQuery and SyncQueryPublisher relationship initializer labels.
- [x] Update demo/runtime and docs to renamed labels.
- [x] Run targeted `swift test --filter SyncQuery` and verify green.

## Last known state
`swift test --filter SyncQuery` and `swift test --filter SyncQueryPublisherTests` green after full rename to `relationship`/`relationshipID`

## Decisions (don't revisit)
- Keep `SyncQuery` base and `predicate` initializers; remove only relationship overloads that infer relationships when explicit relationship alternatives exist.
- Remove `relatedTo:` where explicit relationship key paths already provide related model typing.
- No backward compatibility for label rename: replace `through`/`relatedID` with `relationship`/`relationshipID` everywhere.

## Files touched
- .agents/state.md
- SwiftSync/Tests/SwiftSyncTests/SyncQueryParentTests.swift
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- SwiftSync/Sources/SwiftSync/ReactiveQuery.swift
- SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift
- SwiftSync/Tests/SwiftSyncTests/SyncQueryPublisherTests.swift
- README.md
- docs/project/reactive-reads.md
- docs/project/parent-scope.md
- docs/project/faq.md
- ARCHITECTURE.md
- docs/planning/demo-coverage-gap.md
