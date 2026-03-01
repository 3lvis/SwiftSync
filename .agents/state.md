# State Capsule

## Plan
- [x] Write .agents/state.md (this file)
- [x] Delete TaskDetailSheet enum, actionMenu, all 4 sheets, and `activeSheet` state from TaskDetailView.swift
- [x] Add `@State var showingEditSheet: Bool = false` and replace toolbar with single Edit button
- [x] Implement `EditTaskSheet` — Form with Title (TextEditor), Description, State, Assignee, Reviewers, Watchers sections; Cancel/Save toolbar; no live model mutation
- [x] UI tweaks: multiline title in edit modal; split People into Assignee/Reviewers/Watchers sections in detail view
- [x] Investigate and fix stale reviewers/watchers after save — SwiftData dirty-tracking gap on iOS persistent stores; fixed via syncMarkChanged() in syncApplyToManyForeignKeys
- [x] Add regression test (persistent store, one-sided relationship model)
- [x] Manually verified working on device

## Last known state
all green — manually confirmed on device, full test suite passing

## Decisions (don't revisit)
- No @Syncable draft() method yet — deferred. Draft is constructed manually at EditTaskSheet init.
- includeNulls skipped — nil optionals always emit NSNull (correct semantics).
- Reviewers/Watchers use dedicated engine methods; updateTask handles scalars only.
- The old ellipsis action menu is removed entirely.
- Detail view remains read-only; all mutations via Edit modal only.
- syncMarkChanged() fix: macOS CoreData doesn't reproduce the dirty-tracking gap, so the test cannot be driven red on the SPM host. iOS behavior confirmed via debug logging. Fix is a no-op scalar self-write (self.id = self.id) on the identity property.

## Files touched
- .agents/state.md
- Demo/Demo/Features/TaskDetail/TaskDetailView.swift
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/SwiftSync/SyncableMacro.swift
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- SwiftSync/Tests/SwiftSyncTests/SyncRelationshipIntegrityTests.swift
