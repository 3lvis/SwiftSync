# State Capsule

## Plan

### Debugging: reviewer/watcher stale-UI bug (branch: debug/reviewer-watcher-stale-ui)
- [x] Create branch from 85b7fa0 and write this state.md
- [x] Instrument `save()` in `EditTaskSheet` — timestamps at start, after `updateTask`, after `replaceTaskReviewers`, after `replaceTaskWatchers`, just before `dismiss()`
- [x] Instrument `DemoSyncEngine.replaceTaskReviewers` / `replaceTaskWatchers` — log entry/exit with timestamps
- [x] Instrument `syncApplyToManyForeignKeys` (Core.swift) — log when membership changes, and explicitly flag that no dirty-mark is performed on the owner
- [x] Instrument `SyncContainer.modelContextDidSave` — log `changedIDs` count and `changedModelTypeNames` per save notification
- [x] Instrument `SyncModelObserver.shouldReload` / `reload` — log every notification received, whether reload fires or skips, and which model ID is being watched
- [x] Instrument `TaskDetailView.peopleSection` — log each render with reviewer/watcher counts
- [x] Commit all instrumentation (fbe0125)

## Last known state
All instrumentation committed. Branch ready to run in Xcode.

## Decisions (don't revisit)
- Branch point is 85b7fa0 (BEFORE the syncMarkChanged fix at 346f048) — this is the exact state that exhibits the bug
- `syncMarkChanged` does NOT exist on this branch; that is the missing piece instrumentation should prove
- Root hypothesis: `syncApplyToManyForeignKeys` writes join-table rows but does NOT dirty the owning Task row → Task's PersistentIdentifier never appears in `modelContextDidSave` updatedIdentifiers → `SyncModelObserver` is never notified → UI stays stale until the 14s background poll
- Scalar changes work because writing any scalar column on the Task model automatically dirties the SwiftData store row
- Using `os_log` via `OSLog` / `Logger` for all instrumentation so output is visible in Console.app and Xcode's debug console with timestamps

## Files touched
- .agents/state.md
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- Demo/Demo/Sync/DemoSyncEngine.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Sources/SwiftSync/ReactiveQuery.swift
