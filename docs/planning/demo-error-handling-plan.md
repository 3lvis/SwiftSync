# Demo App Error Handling Plan

## Open items
- [ ] Add a shared `ErrorPresentationState` model for screen-level errors (message, action label, retry closure).
- [ ] Replace ad-hoc `do/catch` blocks in `DemoRootView` and feature screens with a common `presentError(_:)` helper.
- [ ] Surface thrown bootstrap failures in `DemoRootView` as a blocking error state with retry.
- [ ] Surface project list/detail load failures in `ProjectsViewController` and `ProjectsTabView` with inline retry affordances.
- [ ] Surface task detail load failures in `TaskDetailView` with a visible retry action.
- [ ] Separate metadata load errors from save errors in `TaskFormSheet` and present each with context-specific copy.
- [ ] Add focused `DemoTests` coverage for thrown sync failures propagating to UI-facing error state.
- [ ] Remove `DemoSyncEngine.lastErrorMessage` once all views rely on explicit UI-owned error presentation.
