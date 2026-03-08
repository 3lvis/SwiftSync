# State Capsule

## Plan
- [x] Update parent-scoped sync tests/call sites to require explicit `parentRelationship:`.
- [x] Run targeted tests to capture expected compile failures before removing parent inference APIs.
- [x] Remove parent inference-only sync overloads and inference helper machinery from API.
- [x] Update docs to explicit parent relationship contract.
- [x] Run targeted tests for parent-scoped sync and broader `swift test --filter Sync` verification.

## Last known state
`swift test --filter Sync` green after requiring explicit `parentRelationship:` for parent-scoped sync APIs

## Decisions (don't revisit)
- Keep `SyncQuery` base and `predicate` initializers; remove only relationship overloads that infer relationships when explicit relationship alternatives exist.
- Remove `relatedTo:` where explicit relationship key paths already provide related model typing.
- No backward compatibility for label rename: replace `through`/`relatedID` with `relationship`/`relationshipID` everywhere.
- Require explicit `parentRelationship:` for parent-scoped sync APIs; remove inference-only sync overloads.

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
