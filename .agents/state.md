# State Capsule

## Plan
- [x] Update tests/call sites to use `relationship:` instead of `parentRelationship:` for parent-scoped sync.
- [x] Run targeted tests to confirm expected compile failures before label rename.
- [x] Rename parent-scoped sync API labels from `parentRelationship` to `relationship`.
- [x] Update docs to new parent-scoped sync label.
- [x] Run `swift test --filter Sync` and verify green.

## Last known state
`swift test --filter Sync` green after renaming parent-scoped sync label to `relationship:`

## Decisions (don't revisit)
- Keep `SyncQuery` base and `predicate` initializers; remove only relationship overloads that infer relationships when explicit relationship alternatives exist.
- Remove `relatedTo:` where explicit relationship key paths already provide related model typing.
- No backward compatibility for label rename: replace `through`/`relatedID` with `relationship`/`relationshipID` everywhere.
- Require explicit parent relationship key paths for parent-scoped sync APIs; remove inference-only sync overloads.
- Simplify parent-scoped sync call sites to use `relationship:` label.

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
- SwiftSync/Tests/SwiftSyncTests/SyncTests.swift
- SwiftSync/Sources/SwiftSync/API.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
- docs/project/protocol-hierarchy.md
- docs/planning/export-nested-mode.md
