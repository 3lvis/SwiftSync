# State Capsule

## Plan

- [x] Rewrite `docs/project/reactive-reads.md` with stronger mental model and clearer examples
- [x] Review wording against current conventions and remove weak examples

## Last known state

Reactive reads doc rewritten and reviewed; tests not run (docs-only change)

## Decisions (don't revisit)

- Keep documentation changes behavior-neutral and remove any claim that is not directly verifiable from source or tests.
- Replace ID-only sort examples with realistic UI-oriented sort descriptors (`updatedAt`, `priority`, `name`) to avoid misleading guidance.

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
