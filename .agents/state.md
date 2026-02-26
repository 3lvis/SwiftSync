# State Capsule

## Goal

Collapse `SyncUpdatableModel` + `SyncRelationshipUpdatableModel` into one protocol.

## Current status

- ✅ Done: Protocol merged in Core.swift (applyRelationships moved to SyncUpdatableModel with default no-op)
- ✅ Done: 4 runtime casts eliminated in API.swift (direct calls now)
- ✅ Done: @Syncable macro updated (declaration + implementation)
- ✅ Done: 10 test conformance sites updated
- ✅ Done: Strict FK typing test rewritten to use AutoEmployee/AutoCompany
- ✅ Done: Operations test + OpsCompany/OpsEmployee moved to RelationshipOperationsTests.swift
- ✅ Done: Documentation updated (ARCHITECTURE.md, README.md, protocol-hierarchy.md)
- ✅ Done: All 126 tests passing (96 XCTest + 30 swift-testing)

## Decisions (don't revisit)

- SyncRelationshipOperations stays as-is (will be addressed separately)
- The `relationshipOperations` parameter on all API surfaces stays unchanged
- Free helper functions (syncApplyToOneForeignKey etc.) keep their `operations:` parameter
- testStrictForeignKeyTypingDoesNotCoerceRelationshipIDs stays in IntegrationTests (uses AutoEmployee/AutoCompany now)

## Constraints

- No behavior change — default no-op on applyRelationships matches previous runtime-cast-failing semantics

## Key findings

- SyncRelationshipUpdatableModel was never used as a static generic constraint anywhere
- All 4 uses were runtime `as?` casts in API.swift
- The default extension on old protocol discarded `operations:` parameter silently

## Next steps (exact)

1. Ready for commit

## Files touched

- Sources/Core/Core.swift (protocol merge)
- Sources/SwiftDataBridge/API.swift (runtime cast removal)
- Sources/Macros/SyncableMacro.swift (conformance name)
- Sources/MacrosImplementation/SyncableMacro.swift (conformance name)
- Tests/IntegrationTests/IntegrationTests.swift (conformances + FK test rewrite)
- Tests/IntegrationTests/RelationshipIntegrityRegressionTests.swift (conformances)
- Tests/IntegrationTests/RelationshipOperationsTests.swift (new file — moved ops test)
- ARCHITECTURE.md (protocol hierarchy + things worth reducing)
- README.md (Syncable generates section)
- docs/planning/protocol-hierarchy.md (updated)
