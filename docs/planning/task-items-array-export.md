# Task Items — Inline Relationship Export (Current State)

## Open items

- [ ] Decide whether to move implementation-complete details to `docs/project` and keep only active planning tasks in `docs/planning`.

## Goal

Track only the remaining planning work around inline task item export after the feature has been implemented.

## Current state snapshot

- Task child rows are now named `items` and represented by `Item` in the Demo app.
- Task payloads now embed `items` inline in backend create/update/detail/list responses.
- Item persistence uses the `items` table in `DemoServerSimulator`.
- Task create/update flows use exported inline `items` payloads.
- Task detail rendering uses a direct `@SyncQuery` for `Item` rows scoped by `taskID` to avoid stale relationship snapshots after save.
- Task form supports drag reordering and backend accepts reorder-only updates (`id` + `position`) while preserving title by ID.

## Verification currently in place

- Demo backend regression tests cover:
  - create with inline `items`
  - update with `items` key present (replace semantics)
  - update with `items` key absent (preserve semantics)
  - reorder with `id` + `position` only
  - reorder persistence in both task detail and project list payloads

## Notes

- This file intentionally excludes implementation details to keep planning docs focused on active work.
