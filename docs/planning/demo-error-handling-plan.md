# Demo App Error Handling Plan

## Open items
- [ ] Add failing Demo tests for a shared screen load state machine (`idle`, `loading`, `loaded`, `error`) covering start, success, failure, and retry transitions.
- [ ] Add failing Demo tests for shared error presentation mapping (`presentError(_:)`) to ensure message fallback and optional retry action label behavior are consistent.
- [ ] Implement shared UI error primitives (`ErrorPresentationState`, load state enum, and `presentError(_:)`) in Demo runtime code to satisfy the new tests.
- [ ] Add failing tests for project list/detail initial-sync failure behavior, then refactor `ProjectsViewController` and `ProjectsTabView` to use the load state machine with visible retry affordances.
- [ ] Add failing tests for task-detail initial-sync failure behavior, then refactor `TaskDetailView` to use the load state machine with a visible retry action.
- [ ] Add failing tests for `TaskFormSheet` to split metadata-load failures from save-submit failures, then implement separate state and context-specific error copy/actions.
- [ ] Add failing tests that prove screen-level error presentation no longer depends on `DemoSyncEngine.lastErrorMessage`, then remove `lastErrorMessage` and remove the global error banner from `DemoRootView`.
- [ ] Run `swift test`, record manual QA verification steps for loading error and retry paths, and update this plan with only any remaining active follow-up items.
