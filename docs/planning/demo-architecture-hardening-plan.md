# Demo Architecture Hardening Plan

## Goal

Raise the Demo feature architecture from pragmatic to consistently testable and deterministic without expanding product scope.

## Current strengths

- Feature machines now own most load state and reactive data wiring.
- Screens are closer to declarative adapters (render machine state, dispatch events).
- Error handling is screen-scoped instead of global.

## Gaps to close

- Machine code is tightly coupled to concrete infrastructure (`DemoSyncEngine`, `SyncQueryPublisher`, `ModelContext`), which limits fast unit tests.
- Transition logic is split between feature types and helper machines, which increases cognitive load.
- Mutation failure handling is inconsistent; some failures are intentionally swallowed without a documented policy.
- `TaskFormSheet` still keeps item-edit orchestration in the view, leaving feature behavior split across layers.

## Implementation approach

1. Introduce explicit dependency ports so machines consume protocols instead of concrete engine/query/storage types.
2. Make per-feature state transitions explicit through one reducer surface (`State`, `Event`, `Effect`, `reduce`) and one effect runner.
3. Define one mutation-failure policy and apply it consistently (user-visible message or explicit no-op rationale).
4. Move remaining task-form editing orchestration into `TaskFormMachine` so the sheet is render/dispatch only.

## Open items

- [ ] Add protocol ports for sync operations, query streams, and metadata access; inject protocol-backed dependencies into all four feature machines.
- [ ] Refactor each of the four feature machines to a single reducer/effect pattern and remove duplicated transition logic.
- [ ] Implement and document one mutation-failure policy, then update delete/save paths to follow it consistently.
- [ ] Move task item add/delete/reorder orchestration from `TaskFormSheet` into `TaskFormMachine` commands.
- [ ] Add focused machine tests that validate reducer transitions and failure/success effect handling through protocol mocks.
