# State Capsule

## Plan
- [x] CreateTaskSheet: remove insert-upfront, remove cancelAndDiscard delete+rollback, remove failure-path delete+rollback — draft is never inserted so no cleanup needed
- [x] EditTaskSheet: replace manual `[String: Any]` dict in `save()` with inline `Task(...)` construction from existing @State vars + `exportObject(for:syncContainer:relationshipMode:)`
- [x] Merge CreateTaskSheet + EditTaskSheet → TaskFormSheet (TaskFormMode enum, single @State var draft: Task, no scalar draft vars)
- [x] Update `docs/planning/demo-draft-model-export.md`
- [x] Run `swift test` — confirm green

## Last known state
112 + 30 tests green (2026-03-03)

## Decisions (don't revisit)
- No `draft()` macro generation in this pass — that is a future improvement. This pass only makes the existing code correct: uninserted draft for create, exportObject for update.
- EditTaskSheet already has scalar @State draft vars — keep them. At save(), construct Task(...) from those vars inline and call exportObject. No SwiftUI binding restructure needed (that comes with draft() macro pass).
- CreateTaskSheet already has the Task uninserted... wait: it DOES insert at line 226 (`syncContainer.mainContext.insert(task)`). Remove that insert and the corresponding cancelAndDiscard delete+rollback and failure-path delete+rollback.
- stateLabel is stored separately in EditTaskSheet (draftStateLabel) because the state picker picks by id only — the label must be resolved from taskStateOptions at save() time, not stored as a separate @State var that goes stale.

## Files touched
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- docs/planning/demo-draft-model-export.md
