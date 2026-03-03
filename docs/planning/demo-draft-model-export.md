# Demo: Draft Model Pattern for Export

**Status:** Planned  
**Priority:** High — current workaround (manual dict overrides) defeats the purpose of the export system

---

## Problem

The demo's update flow currently defeats the export system's purpose. After investigating the bug where mutating a live `taskModel` before the API call caused a background-context merge conflict, we reverted to manually injecting overrides into the exported dict:

```swift
// Current workaround — state change
var body = taskModel.exportObject(for: syncContainer, relationshipMode: .none)
body["state"] = ["id": option.id] as [String: Any]   // ← manual dict surgery

// Current workaround — description
var body = taskModel.exportObject(for: syncContainer, relationshipMode: .none)
body["description"] = trimmed                          // ← manual dict surgery

// Current workaround — assignee
var body = taskModel.exportObject(for: syncContainer, relationshipMode: .none)
body["assignee_id"] = pendingAssigneeID ?? NSNull()    // ← manual dict surgery
```

This is worse than the old `buildUpdateTaskBody` approach — it uses export for some fields and raw dict manipulation for others. The key invariants of `@RemoteKey`, `@RemotePath`, and key style transforms are bypassed for the overridden fields.

The right model is: the UI holds an **editable draft** of the object, mutates it freely, calls `exportObject` on the draft, and passes the result to the engine. No live object mutation, no dict surgery.

---

## Root cause of the original bug

Mutating the live `taskModel` (which lives on `mainContext`) before the API call left an unsaved dirty mutation on `mainContext`. The subsequent `syncContainer.sync(item:as:)` operates on a **background context** (`makeBackgroundContext()`). The background context fetches the last **saved** state from the persistent store — not the unsaved dirty state on `mainContext`. After saving the background context, `modelContextDidSave` fires and merges into `mainContext`, but SwiftData's merge logic for an object with competing unsaved mutations drops the incoming changes for conflicting fields (`stateLabel`, `updatedAt`).

The fix is not to avoid export — it's to avoid mutating the live persisted object. A **draft** object that is not the same instance as the persisted `taskModel` can be mutated freely with no effect on `mainContext` or the background merge.

---

## Key finding: uninserted `@Model` objects are safe for `exportObject`

From the test suite (`testApplyReturnsFalseWhenPayloadMatchesExistingValues`, `testApplyReturnsTrueWhenAnyFieldDiffers`): `@Model` objects that have never been inserted into a `ModelContext` have their properties backed by a heap-allocated `DefaultBackingData` buffer initialized at `init` time. Property reads and writes are safe. `apply()` and `exportObject` work correctly on uninserted objects.

This means a draft can be constructed from `Task(...)`, mutated, and exported without any context scaffolding at all.

---

## The draft pattern

### For update (all edit sheets and inline actions)

The UI should hold a **draft** — a separate `Task` instance copied from the current `taskModel` values, with the user's edits applied. The draft is never inserted into any context. It is mutated freely, exported, and then discarded. The re-sync from the server response writes the ground truth back to `mainContext` via the background context path.

```swift
// Conceptual pattern — state change
let draft = Task(
    id: taskModel.id,
    projectID: taskModel.projectID,
    title: taskModel.title,
    descriptionText: taskModel.descriptionText,
    state: option.id,                    // ← override applied on the draft
    stateLabel: taskModel.stateLabel,
    createdAt: taskModel.createdAt,
    updatedAt: taskModel.updatedAt
)
// draft is NOT inserted into any context
let body = draft.exportObject(for: syncContainer, relationshipMode: .none, includeNulls: false)
syncEngine.updateTask(taskID: taskModel.id, projectID: taskModel.projectID, body: body)
// draft goes out of scope — nothing persisted, mainContext untouched
```

The `Task(...)` init call is the "form" — every field is explicit. `@RemoteKey`, `@RemotePath`, and key style transforms are all applied correctly by `exportObject`. No dict surgery needed.

### For richer edit sheets (description, assignee)

Edit sheets that bind a `TextEditor` or a picker to a local `@State` value naturally produce a "draft" value. At save time, construct a `Task` with that value as the override:

```swift
// EditTaskDescriptionSheet
let draft = Task(
    id: taskModel.id,
    ...,
    descriptionText: text,     // ← local @State, trimmed
    ...
)
let body = draft.exportObject(for: syncContainer, relationshipMode: .none, includeNulls: false)
```

---

## The boilerplate concern

The pattern requires listing every field of `Task` at each call site that builds a draft. For a model with many fields this is:
- Error-prone: adding a new field requires updating every draft construction site
- Repetitive: create + 3 update call sites all repeat the same field list

### Proposed solution: `@Syncable` generates `makeDraft(from:)` or `draft()` method

The `@Syncable` macro already knows all scalar fields. It should generate a `draft()` method that returns a new uninserted copy of the object with all scalar fields copied and relationships set to their defaults (nil / []):

```swift
// Generated by @Syncable:
func draft() -> Task {
    Task(
        id: self.id,
        projectID: self.projectID,
        assigneeID: self.assigneeID,
        authorID: self.authorID,
        title: self.title,
        descriptionText: self.descriptionText,
        state: self.state,
        stateLabel: self.stateLabel,
        createdAt: self.createdAt,
        updatedAt: self.updatedAt
    )
}
```

Call sites then become:

```swift
// State change
let draft = taskModel.draft()
draft.state = option.id
let body = draft.exportObject(for: syncContainer, relationshipMode: .none, includeNulls: false)

// Description
let draft = taskModel.draft()
draft.descriptionText = text
let body = draft.exportObject(for: syncContainer, relationshipMode: .none, includeNulls: false)

// Assignee
let draft = taskModel.draft()
draft.assigneeID = pendingAssigneeID
let body = draft.exportObject(for: syncContainer, relationshipMode: .none, includeNulls: false)
```

This is the goal: the UI works with real model objects, mutates them naturally, and calls `exportObject`. No dict surgery, no throwaway containers, no scaffolding.

---

## Execution checklist

- [ ] 1. Verify `exportObject` is safe on an uninserted `@Model` with a targeted test (construct `Task`, do NOT insert, call `exportObject`, assert output)
- [ ] 2. Add `draft()` method generation to `@Syncable` macro — copies all scalar non-relationship fields into a new uninserted instance
- [ ] 3. Add `draft()` to `SyncUpdatableModel` protocol (or as a macro-only generated method)
- [ ] 4. Refactor `TaskDetailView` state change action — use `taskModel.draft()`, set override, `exportObject(for:)`
- [ ] 5. Refactor `EditTaskDescriptionSheet` — use `taskModel.draft()`, set override, `exportObject(for:)`, remove manual `body["description"]` injection
- [ ] 6. Refactor `AssigneePickerSheet` — use `taskModel.draft()`, set override, `exportObject(for:)`, remove manual `body["assignee_id"]` injection
- [ ] 7. Remove manual dict surgery (`body["state"]`, `body["description"]`, `body["assignee_id"]`) from all update call sites
- [ ] 8. Remove rollback calls from update sheets (no live object mutation means no rollback needed)
- [ ] 9. Run full build and test suite
