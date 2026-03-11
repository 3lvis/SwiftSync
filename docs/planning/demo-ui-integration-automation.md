# Demo UI Integration Automation

This plan stages demo app UI automation in two passes.

The first pass should prove the main end-to-end task flows are stable in automation: initial fetch and render, creating items, editing an item, single-field update coverage such as renaming a task title, refreshing data after changes, and deleting items.

The second pass should expand that coverage into edge cases: empty states, repeated updates, cancel paths, stale selection after deletes, reload timing, list/detail synchronization, and any regressions caused by partial edits or rapid user interaction.

## Open items

- [ ] Inventory the current Demo app surfaces, controls, and accessibility identifiers needed to drive task-list UI automation reliably
- [ ] Define a baseline UI automation suite for initial fetch and loaded-state verification in the demo app
- [ ] Define a baseline UI automation suite for adding a new task and asserting it appears in the expected list state
- [ ] Define a baseline UI automation suite for editing an existing task and asserting the persisted values reload correctly
- [ ] Define a baseline UI automation suite for a single-field task-title update to isolate the smallest meaningful change flow
- [ ] Define a baseline UI automation suite for deleting a task and asserting the removal is reflected in both UI state and subsequent fetches
- [ ] Define a baseline UI automation suite for mixed fetch-change-update-remove sequencing so the core CRUD path is exercised in one end-to-end run
- [ ] Identify the test data seeding or backend reset strategy needed so baseline UI automation runs are deterministic
- [ ] Identify the launch arguments, environment flags, and fixtures needed to keep demo UI automation independent from manual backend state
- [ ] Define the first edge-case suite for empty fetch results, no-op edits, cancel flows, and validation-safe partial edits
- [ ] Define the next edge-case suite for repeated title updates, rapid add-delete cycles, and deleting an item that is currently selected or being viewed
- [ ] Define edge-case coverage for refresh or re-fetch timing so remote or async updates do not leave stale rows or stale detail content on screen
- [ ] Define how UI automation assertions should distinguish expected sync progress indicators from failed or hung state transitions
- [ ] Define the build-and-test workflow for demo UI automation so baseline coverage lands first and edge cases expand incrementally without destabilizing CI
