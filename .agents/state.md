# State Capsule

## Plan
- [~] Write .agents/state.md (this file)
- [ ] Delete TaskDetailSheet enum, actionMenu, all 4 sheets (EditTaskDescriptionSheet, AssigneePickerSheet, EditTaskReviewersSheet, EditTaskWatchersSheet), and `activeSheet` state from TaskDetailView.swift
- [ ] Add `@State var showingEditSheet: Bool = false` and replace toolbar with single Edit button
- [ ] Implement `EditTaskSheet` private struct inside TaskDetailView.swift:
  - Uninserted draft Task (constructed from live taskModel at init time — no @Syncable draft() yet)
  - Local `reviewerIDs: Set<String>` and `watcherIDs: Set<String>`
  - Form with sections: Title (TextField), Description (TextEditor), State (checkmark rows), Assignee (checkmark rows), Reviewers (multi-select checkmarks), Watchers (multi-select checkmarks)
  - Toolbar: Cancel (leading) + Save (trailing, with ProgressView while saving)
  - Save: exportObject on draft → updateTask; if reviewers changed → replaceTaskReviewers; if watchers changed → replaceTaskWatchers
  - Cancel: dismiss, draft discarded — no rollback needed (live model never mutated)
- [ ] Build Demo and verify it compiles

## Last known state
tests green, Demo builds clean

## Decisions (don't revisit)
- No @Syncable draft() method yet — that is deferred to a follow-up task. Draft is constructed manually at EditTaskSheet init: `Task(id: taskModel.id, projectID: ..., ...)`.
- includeNulls skipped — nil optionals always emit NSNull (correct semantics).
- Reviewers and Watchers use dedicated engine methods (replaceTaskReviewers / replaceTaskWatchers), not updateTask.
- Error handling: show alert on any save failure; partial saves (scalar OK but reviewers fail) are acceptable.
- The old ellipsis action menu is removed entirely — no "keep menu + add Edit item" hybrid.
- Detail view remains read-only; all mutations via Edit modal only.

## Files touched
- .agents/state.md
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
