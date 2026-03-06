# ExportRelationshipMode.nested — Historical Analysis (Removed)

## Open items

- [ ] Sweep remaining docs/examples to ensure `.nested` snippets are clearly labeled historical.
- [ ] Decide whether to move this file to an archive/history location once no follow-up work remains.

## Current state

`.nested` has been removed from the public API surface.

This document is retained as historical analysis for why the mode was removed.

---

## What `.nested` did

`ExportRelationshipMode.nested` produces Rails `accepts_nested_attributes_for`-style payloads.

**To-one relationship** (`assignee: User?`):
```json
{ "assignee_attributes": { "id": "u1", "display_name": "Alice" } }
```

**To-many relationship** (`reviewers: [User]`):
```json
{
  "reviewers_attributes": {
    "0": { "id": "u1", "display_name": "Alice" },
    "1": { "id": "u2", "display_name": "Bob" }
  }
}
```

The key is always `<propertyName>_attributes`. For to-many, children are keyed by integer
index string. This is exactly what Rails generates and expects when a model uses
`accepts_nested_attributes_for`.

---

## Why it cannot be dropped into the demo as-is

The demo's backend models all relationships as scalar FKs or flat ID arrays — neither is
compatible with `_attributes`-style bodies:

| Relationship | Demo wire format | What `.nested` produces |
|---|---|---|
| `Task.assignee` (to-one) | `"assignee_id": "u1"` | `"assignee_attributes": { ... }` |
| `Task.project` (to-one) | `"project_id": "p1"` | `"project_attributes": { ... }` |
| `Task.reviewers` (to-many) | `"reviewer_ids": ["u1", "u2"]` | `"reviewers_attributes": { "0": { ... }, ... }` |
| `Task.watchers` (to-many) | `"watcher_ids": ["u1", "u2"]` | `"watchers_attributes": { "0": { ... }, ... }` |

The demo's `DemoServerSimulator` had no endpoints that accepted `_attributes`-style bodies.
Calling `.nested` export on a `Task` would have produced a payload the backend would
silently ignore or reject on every field above.

---

## What a real integration requires

`.nested` is only meaningful when:

1. The server uses `accepts_nested_attributes_for` (Rails) or an equivalent convention
   that accepts inline child-object graphs inside a parent write request.
2. The use case is **create-or-update-with-children-in-one-request** — inserting a parent
   record that simultaneously creates or updates its children atomically.

The demo's fake server is not a Rails app and had no `_attributes` routes. Bolting `.nested`
onto an existing `Task` relationship would have required rewriting `DemoServerSimulator`'s SQL
and the `FakeDemoAPIClient` contract, which changes the demo's purpose from illustrating
SwiftSync to illustrating Rails interop.

---

## A concrete scenario that would fit honestly

The smallest addition that gives `.nested` a real end-to-end path: add a `Comment` model,
where creating a task can optionally include an initial comment inline in one request.

### Server side (`DemoServerSimulator`)

Add a `comments` table:
```sql
CREATE TABLE comments (
    id    TEXT PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    body  TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

Extend the `createTask` handler: if `comments_attributes` is present in the request body,
insert each child comment in the same transaction as the task insert.

### Client side — new `Comment` model

```swift
@Syncable @Model final class Comment {
    @Attribute(.unique) var id: String
    var body: String
    var createdAt: Date
    var task: Task?
}
```

Add to `Task`:
```swift
@Relationship(inverse: \Comment.task) var comments: [Comment]
```

### Create flow in `CreateTaskSheet`

When the user writes an initial comment, insert a `Comment` into the context and attach it
to the draft `Task`. Historical API call (before removal):

```swift
let body = draft.exportObject(for: syncContainer, relationshipMode: .nested)
```

This produces:
```json
{
  "id": "...",
  "title": "Buy milk",
  "description": "...",
  "comments_attributes": {
    "0": { "id": "...", "body": "First comment", "created_at": "..." }
  }
}
```

The server inserts both the task and the comment atomically. The client then syncs the
task's comments back via a normal `getTaskComments` → `syncContainer.sync(payload:as:parent:)`
call.

This is the smallest honest demonstration: one new model, one new `_attributes` key, one
create endpoint that handles it, no changes to the existing task or user models.

---

## Resolution

**Option B chosen (2026-03-04):** `.nested` removed from the API surface.

`ExportRelationshipMode.nested` was speculative — no concrete consumer existed in the demo
or in any known app. `.array` covers non-Rails backends. The Rails-specific `_attributes`
wire format is not a general REST convention, and SwiftSync does not target Rails backends
exclusively. Removed in branch `remove-nested-export-mode`.
