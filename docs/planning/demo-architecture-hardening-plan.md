# Demo Architecture Hardening Plan

## Goal

Raise the Demo feature architecture from pragmatic to consistently testable and deterministic without expanding product scope.

## Open items

- [ ] Extract all non-UI demo code into `DemoCore` (models, networking, sync engine, runtime, reducers, and feature machines).
- [ ] Keep `Demo/Demo/**` UI-only and remove demo app unit-test coverage.
- [ ] Add protocol ports for sync operations, query streams, and metadata access; inject protocol-backed dependencies into all four feature machines.
- [ ] Refactor each feature machine to a single reducer/effect surface and remove duplicated transition logic.
- [ ] Define one mutation-failure policy and apply it consistently across delete/save paths.
- [ ] Add focused `DemoCoreTests` coverage for reducer transitions and failure/success effect handling.
