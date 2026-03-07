# State Capsule

## Plan
- [x] Define minimal RemoteKey-only parity test matrix (no optional/redundant cases)
- [x] Add RemoteKey parity tests first in sync/export suites and remove RemotePath usage
- [x] Run targeted tests to confirm expected failures
- [x] Implement smallest code changes so RemoteKey covers selected realistic scenarios
- [x] Remove RemotePath public API and macro implementation (no compatibility layer)
- [x] Run targeted tests, then full `swift test`
- [x] Update docs/planning item to reflect verified status

## Last known state
`swift test` in `SwiftSync/` passes (115 tests, 0 failures)

## Decisions (don't revisit)
- Keep the matrix minimal and non-redundant per request; exclude optional scenarios from earlier plan.
- Remove `@RemotePath` with no backwards compatibility as explicitly requested.

## Files touched
- .agents/state.md
- SwiftSync/Tests/SwiftSyncTests/SyncTests.swift
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- SwiftSync/Sources/SwiftSync/SyncableMacro.swift
- docs/planning/demo-coverage-gap.md
- docs/project/faq.md
- docs/project/property-mapping-contract.md
- README.md
- ARCHITECTURE.md
