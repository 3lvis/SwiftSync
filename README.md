![SwiftSync](Images/logo-v3.png)

SwiftSync is a sync layer for SwiftData apps.

You define models once, read from local SwiftData, and let SwiftSync handle the repetitive JSON sync/export work in between.

## Features

- Convention-first JSON -> SwiftData mapping
- Deterministic diffing for inserts, updates, and deletes
- Automatic relationship syncing for nested objects and foreign keys
- Export back into API-ready JSON
- Reactive local reads for SwiftUI and UIKit

## Quick Start

### Mark your models as @Syncable

![Relationship model example](Images/one-to-many-swift.png)

```swift
import SwiftData
import SwiftSync

@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var email: String?
  var createdAt: Date?
  var updatedAt: Date?
  var notes: [Note]

  init(id: Int, email: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil, notes: [Note] = []) {
    self.id = id
    self.email = email
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.notes = notes
  }
}

@Syncable
@Model
final class Note {
  @Attribute(.unique) var id: Int
  var text: String
  var user: User?

  init(id: Int, text: String, user: User? = nil) {
    self.id = id
    self.text = text
    self.user = user
  }
}
```

### JSON

```json
[
  {
    "id": 6,
    "email": "shawn@ovium.com",
    "created_at": "2014-02-14T04:30:10+00:00",
    "updated_at": "2014-02-17T10:01:12+00:00",
    "notes": [
      {
        "id": 301,
        "text": "Call supplier before Friday"
      },
      {
        "id": 302,
        "text": "Prepare Q1 budget review"
      }
    ]
  }
]
```

### Setup SwiftSync and call sync with your JSON

In your root:

```swift
let syncContainer = try SyncContainer(for: User.self, Note.self)
```

In your network layer:

```swift
let payload = try await getUsers()
try await syncContainer.sync(payload: payload, as: User.self)
```

### SwiftUI reacts automatically to changes using @SyncQuery

```swift
import SwiftUI
import SwiftSync

struct UsersView: View {
  let syncContainer: SyncContainer

  @SyncQuery(
    User.self,
    in: syncContainer,
    sortBy: [SortDescriptor(\User.email)]
  )
  private var users: [User]

  var body: some View {
    List(users) { user in
      Section(user.email ?? "User \\(user.id)") {
        ForEach(user.notes) { note in
          Text(note.text)
        }
      }
    }
  }
}
```

## Install

Add the package in Xcode:

1. `File` -> `Add Package Dependencies...`
2. Use this URL:

```text
https://github.com/3lvis/SwiftSync.git
```

3. Add the `SwiftSync` library product to your app target.

If you use `Package.swift` directly:

```swift
.package(url: "https://github.com/3lvis/SwiftSync.git", from: "1.0.0")
```

Then import:

```swift
import SwiftSync
```

Requirements: Xcode 17+, Swift 6.2, iOS 17+ / macOS 14+

## Full Overview

The fastest way to understand SwiftSync is to follow the demo app.

The demo is a small project-tracking app backed by a simulated API. It includes root collections (`projects`, `users`, `task-state-options`), parent-scoped children (`/projects/{id}/tasks`), task detail payloads with nested checklist items, and task editing flows that mutate scalar fields, to-one links, and to-many people relationships.

Table of contents:

- [Demo App](#demo-app)
- [Case Study: Projects](#case-study-projects)
- [Case Study: Project Tasks](#case-study-project-tasks)
- [Case Study: Task Detail](#case-study-task-detail)
- [Case Study: Task Form Metadata](#case-study-task-form-metadata)
- [Property Mapping and Customization](#property-mapping-and-customization)
- [Reactive Reads](#reactive-reads)
- [Exporting JSON](#exporting-json)
- [Date Handling](#date-handling)
- [Further Reading](#further-reading)
- [License](#license)

## Demo App

The demo app is the best overview because it exercises the full intended workflow instead of isolated toy snippets.

It shows:

- a `Project -> Task -> Item` model graph in SwiftData
- `User` reference data reused across assignee, author, reviewers, and watchers
- root sync for shared lookup tables and project lists
- parent-scoped sync for project tasks and task items
- task creation and editing flows that export local drafts back into API payloads
- SwiftUI and UIKit reads that stay in sync with the local store
- network scenario presets (`Fast Stable`, `Slow Network`, `Flaky Network`, `Offline`) so you can see the local-first read model under unstable conditions

To review it, open `SwiftSync.xcworkspace`.

## Case Study: Projects

This is the top-level collection case: one endpoint returns the current list of projects, and SwiftSync diffs that collection into the local store.

### Model

```swift
@Syncable
@Model
public final class Project {
  @Attribute(.unique) public var id: String
  public var name: String
  public var taskCount: Int
  public var createdAt: Date
  public var updatedAt: Date
  public var tasks: [Task]
}
```

### JSON

```json
[
  {
    "id": "C3E7A1B2-1001-0000-0000-000000000001",
    "name": "Account Security Controls",
    "task_count": 5,
    "created_at": "2025-01-01T09:00:00Z",
    "updated_at": "2025-01-01T09:00:00Z"
  }
]
```

### Sync

```swift
let payload = try await apiClient.getProjects()
try await syncContainer.sync(payload: payload, as: Project.self)
```

This is the "replace this collection with the server's current truth" path: insert new rows, update existing ones, and remove rows no longer present.

### Read

```swift
let rowsPublisher = SyncQueryPublisher(
  Project.self,
  in: syncContainer,
  sortBy: [SortDescriptor(\Project.name), SortDescriptor(\Project.id)]
)
```

This is the default SwiftSync shape: stable identity, mostly convention-matched scalar fields, and a relationship filled later by a more specific endpoint.

## Case Study: Project Tasks

The demo does not fetch every task globally. Instead, `/projects/{id}/tasks` returns the tasks for one project, which makes this a parent-scoped sync.

### Model

```swift
@Syncable
@Model
public final class Task {
  @Attribute(.unique) public var id: String
  public var projectID: String
  public var assigneeID: String?
  public var authorID: String
  public var title: String
  public var createdAt: Date
  public var updatedAt: Date

  @NotExport
  public var project: Project?
}
```

### JSON

```json
[
  {
    "id": "C3E7A1B2-3001-0000-0000-000000000001",
    "project_id": "C3E7A1B2-1001-0000-0000-000000000001",
    "author_id": "C3E7A1B2-2001-0000-0000-000000000004",
    "assignee_id": "C3E7A1B2-2001-0000-0000-000000000001",
    "title": "Add session timeout controls to account settings",
    "created_at": "2025-01-01T05:00:00Z",
    "updated_at": "2025-01-01T05:00:00Z"
  }
]
```

### Sync

```swift
try await syncContainer.sync(
  payload: payload,
  as: Task.self,
  parent: project,
  relationship: \Task.project
)
```

The explicit `relationship:` key path is required at the API boundary so the scope is unambiguous.

### Read

```swift
let taskPublisher = SyncQueryPublisher(
  Task.self,
  relationship: \Task.project,
  relationshipID: projectID,
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.updatedAt, order: .reverse),
    SortDescriptor(\Task.id)
  ]
)
```

The quick start already covered the basic nested to-many case. The demo expands that into a more realistic child model where tasks also carry scalar foreign keys like `projectID`, `authorID`, and `assigneeID`, plus related `User` rows loaded from shared reference data.

Payload semantics remain strict:

- absent key means ignore
- explicit `null` means clear

## Case Study: Task Detail

The task detail screen shows a different pattern: one endpoint returns a single task plus nested checklist items.

### Model

```swift
@Syncable
@Model
public final class Item {
  @Attribute(.unique) public var id: String
  public var taskID: String
  public var title: String
  public var position: Int

  @NotExport
  public var task: Task?
}
```

### JSON

```json
{
  "id": "C3E7A1B2-3001-0000-0000-000000000001",
  "project_id": "C3E7A1B2-1001-0000-0000-000000000001",
  "title": "Add session timeout controls to account settings",
  "items": [
    {
      "id": "C3E7A1B2-4001-0000-0000-000000000001",
      "task_id": "C3E7A1B2-3001-0000-0000-000000000001",
      "title": "Document requirements",
      "position": 0
    }
  ]
}
```

### Sync

```swift
try await syncContainer.sync(item: payload, as: Task.self)
try await syncContainer.sync(
  payload: itemPayload,
  as: Item.self,
  parent: task,
  relationship: \Item.task
)
```

### Read

```swift
public var task: Task? {
  taskPublisher.row
}

public var items: [Item] {
  itemPublisher.rows
}
```

This is useful when the parent row is globally identifiable but one nested child collection is scoped to the detail payload. The result is:

- `sync(item:)` updates the one task row without treating the payload as a full collection diff
- checklist items are diffed only within that task's scope
- list screens and detail screens keep reading from the same local SwiftData state

## Case Study: Task Form Metadata

The task form combines shared lookup data, scalar fields, and to-many people relationships.

### Model

```swift
@Syncable
@Model
public final class TaskStateOption {
  @Attribute(.unique) public var id: String
  public var label: String
  public var sortOrder: Int
}
```

The same form also depends on:

- `User` rows for authors, assignees, reviewers, and watchers
- `Task` fields like `assigneeID`, `state`, `stateLabel`, `reviewers`, and `watchers`

### JSON

```json
{
  "project_id": "C3E7A1B2-1001-0000-0000-000000000001",
  "title": "Validate security policy PATCH payload",
  "description": "Protect the API contract for security settings updates.",
  "state": { "id": "todo" },
  "assignee_id": "C3E7A1B2-2001-0000-0000-000000000002"
}
```

### Sync

```swift
try await syncUsersData()
try await syncTaskStatesData()
```

Then task edits export local form state back into JSON, send it to the backend, and sync the authoritative response back into SwiftData.

### Why this matters

This part of the demo shows several non-trivial cases:

- a to-one relationship represented by a scalar foreign key (`assigneeID`)
- multiple roles pointing at the same model type (`author`, `assignee`, `reviewers`, `watchers`)
- to-many relationships maintained by explicit ID replacement endpoints
- the local UI reading immediately from SwiftData instead of waiting for view-specific DTOs

## Property Mapping and Customization

Most of the demo uses convention-first mapping, but the `Task` model also shows where customization belongs.

### Model

`description` is a backend key, but the local property is named `descriptionText`:

```swift
@RemoteKey("description")
public var descriptionText: String?
```

The task state is also modeled as a nested object in the payload while remaining flat in the local model:

```swift
@RemoteKey("state.id")
public var state: String

@RemoteKey("state.label")
public var stateLabel: String
```

### JSON

```json
{
  "description": "Protect the API contract for security settings updates.",
  "state": {
    "id": "todo",
    "label": "To Do"
  }
}
```

### Mapping

That is the intended shape for customization:

- rely on convention when names already line up
- use `@RemoteKey` when the local property name intentionally differs
- use deep paths when the backend nests values but your local model should stay flat

Relationships that should not be exported wholesale back to the server are marked `@NotExport` in the demo. That keeps export focused on the API contract instead of mirroring the entire local object graph.

For identity selection:

1. `@PrimaryKey` or `@PrimaryKey(remote: ...)`
2. `id`
3. `remoteID`

## Reactive Reads

The demo reads everything from local SwiftData using reactive queries. That is the key architectural shift: sync writes into the local store, and screens observe the store instead of binding directly to network responses.

Use `@SyncQuery` for list reads and `@SyncModel` for detail reads.

```swift
@SyncQuery(
  Task.self,
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.updatedAt, order: .reverse),
    SortDescriptor(\Task.id)
  ]
)
var tasks: [Task]
```

For relationship-scoped reads, pass `relationship` and `relationshipID`:

```swift
@SyncQuery(
  Task.self,
  relationship: \.project,
  relationshipID: projectID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.id)]
)
var tasks: [Task]
```

Use `predicate` instead when `relationship/relationshipID` is not the right shape:

- screens that only have scalar IDs (no related model instance)
- non-parent filters (for example `assigneeID == userID`)
- compound business filters (for example status + date window + membership)

### UIKit / State Machines

UIKit is supported via `SyncQueryPublisher` and `SyncModelPublisher`.
See [Reactive Reads](docs/project/reactive-reads.md) for the full patterns.

## Exporting JSON

The demo form flow exports local draft state back into request payloads before sending mutations:

```swift
let body = draft.exportObject(for: syncContainer)
```

For bulk export, use:

```swift
let rows = try syncContainer.export(as: User.self)
```

Defaults:

- snake_case keys
- relationships included as inline arrays/objects
- ISO-style UTC dates
- nils exported as `null`

To exclude a relationship from all exports, apply `@NotExport` to the property.

Use camelCase by configuring the container:

```swift
let syncContainer = SyncContainer(modelContainer, keyStyle: .camelCase)
let rows = try syncContainer.export(as: User.self)
```

Export only the children for one parent:

```swift
let rows = try syncContainer.export(as: Item.self, parent: task)
```

## Date Handling

The demo uses normal API timestamps on every model (`createdAt`, `updatedAt`) so you can see date parsing in a realistic setup instead of an isolated test model.

Inbound parsing supports common ISO8601 variants, date-only strings, `YYYY-MM-DD HH:mm:ss`, fractional seconds, and unix timestamps. In practice, if your backend sends ordinary app timestamps, SwiftSync is designed to accept them without extra formatter plumbing.

## Further Reading

- [Reactive Reads](docs/project/reactive-reads.md)
- [Backend Contract](docs/project/backend-contract.md)
- [FAQ](docs/project/faq.md)

## License

SwiftSync is released under the [MIT License](LICENSE).
