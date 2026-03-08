# Demo App Error Handling Plan

## Open items
- [ ] Add a shared `ErrorPresentationState` model for screen-level errors (message, action label, retry closure).
- [ ] Replace ad-hoc `do/catch` blocks in `DemoRootView` and feature screens with a common `presentError(_:)` helper.
- [ ] Surface thrown project sync failures in `ProjectsViewController` and `ProjectsTabView` with inline retry affordances.
- [ ] Surface thrown task detail sync failures in `TaskDetailView` with a visible retry action.
- [ ] Separate metadata load errors from save errors in `TaskFormSheet` and present each with context-specific copy.
- [ ] Add focused verification notes for thrown sync failures in manual QA steps and backend/SwiftSync test runs.
- [ ] Remove `DemoSyncEngine.lastErrorMessage` once all views rely on explicit UI-owned error presentation.
