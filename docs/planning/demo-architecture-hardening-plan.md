# Demo Architecture Hardening Plan

## Goal

Raise the Demo feature architecture from pragmatic to consistently testable and deterministic without expanding product scope.

## Open items

- [ ] Add protocol ports for sync operations, query streams, and metadata access; inject protocol-backed dependencies into all four feature machines.
- [ ] Refactor each feature machine to a single reducer/effect surface and remove duplicated transition logic.
- [ ] Define one mutation-failure policy and apply it consistently across delete/save paths.
- [ ] Move remaining task item add/delete/reorder orchestration from `TaskFormSheet` into `TaskFormMachine` commands.
- [ ] Add focused machine tests that validate reducer transitions and failure/success effect handling through protocol mocks.
