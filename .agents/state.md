# State Capsule

## Plan

- [x] Review repository state and collect current documentation files
- [x] Audit documentation content against current source and tests
- [x] Update docs to remove stale claims and keep only verified behavior
- [x] Run swift test to verify documented behavior still matches code

## Last known state

`swift test` passed (119 XCTest + 48 Swift Testing assertions)

## Decisions (don't revisit)

- Keep documentation changes behavior-neutral and remove any claim that is not directly verifiable from source or tests.

## Files touched

- .agents/state.md
- README.md
- ARCHITECTURE.md
- docs/README.md
- docs/project/backend-contract.md
- docs/project/faq.md
- docs/project/ios-dirty-tracking-gap.md
- docs/project/property-mapping-contract.md
- docs/project/protocol-hierarchy.md
- docs/project/reactive-reads.md
- docs/project/relationship-integrity.md
- docs/project/sendable-playbook.md
