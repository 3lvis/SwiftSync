# State Capsule

## Plan
- [x] CreateTaskSheet: remove insert-upfront, remove cancelAndDiscard delete+rollback, remove failure-path delete+rollback — draft is never inserted so no cleanup needed
- [x] EditTaskSheet: replace manual `[String: Any]` dict in `save()` with inline `Task(...)` construction from existing @State vars + `exportObject(for:syncContainer:relationshipMode:)`
- [x] Merge CreateTaskSheet + EditTaskSheet → TaskFormSheet (TaskFormMode enum, single @State var draft: Task, no scalar draft vars)
- [x] Refactor TaskFormSheet to use throwaway ModelContext for draft (edit fetches by ID into autosave-disabled context; create inserts into same; reviewers/watchers are real [User] objects — no Set<String> tracking)
- [x] Add reviewers/watchers sections to create form; send via replaceTaskReviewers/replaceTaskWatchers post-create
- [x] Fix updateTask sync ordering bug — syncTaskDetailInternal must run last (authoritative over project list snapshot)
- [x] Extract syncTaskAfterMutation helper to enforce list-then-detail ordering in one place
- [x] Fix task states loading spinner on form open — fetch from disk first, network only if store is empty
- [x] Update `docs/planning/demo-draft-model-export.md`
- [x] Run `swift test` — confirm green

## Last known state
112 + 30 tests green (2026-03-04)

## Decisions (don't revisit)
- No `draft()` macro generation in this pass — that is a future improvement. This pass only makes the existing code correct: uninserted draft for create, exportObject for update.
- EditTaskSheet already has scalar @State draft vars — keep them. At save(), construct Task(...) from those vars inline and call exportObject. No SwiftUI binding restructure needed (that comes with draft() macro pass).
- CreateTaskSheet already has the Task uninserted... wait: it DOES insert at line 226 (`syncContainer.mainContext.insert(task)`). Remove that insert and the corresponding cancelAndDiscard delete+rollback and failure-path delete+rollback.
- stateLabel is stored separately in EditTaskSheet (draftStateLabel) because the state picker picks by id only — the label must be resolved from taskStateOptions at save() time, not stored as a separate @State var that goes stale.
- throwaway ModelContext pattern chosen over plain struct draft — relationships (reviewers, watchers) are real [User] objects from the same context, so assignment is safe and no ID-set translation is needed.
- syncTaskAfterMutation ordering: project list first, task detail last. Detail is authoritative for relationship data and must win over any stale list snapshot.
- disk-first for task states: fetch from editContext immediately, only call syncEngine.syncTaskStates() if store is empty. Ad-hoc fix in TaskFormSheet — full engine-level cache-first pattern deferred to docs/planning/engine-cache-first-sync.md.

## Files touched
- Demo/Demo/Features/Projects/ProjectsTabView.swift
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Features/TaskFormSheet.swift
- Demo/Demo/Models/DemoModels.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
- docs/planning/demo-draft-model-export.md
- docs/planning/engine-cache-first-sync.md
