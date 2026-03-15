# SwiftSync

![SwiftSync](Images/logo-v3.png)

SwiftSync is a sync layer for SwiftData apps with JSON backends.

It is the SwiftData-era successor to the old Core Data library `Sync`.
If you are coming from legacy `Sync`, start with [Migrating From Sync](docs/project/migrating-from-sync.md).

You define models once, then use one API to:
- sync server payloads into local SwiftData
- export local SwiftData back into API-ready JSON

It follows convention over configuration and keeps behavior deterministic.

The promise is simple:
- your app reads from local SwiftData
- your backend speaks normal JSON
- SwiftSync handles the repetitive glue in between

Core features:
- convention-first JSON -> SwiftData mapping
- deterministic diffing for inserts, updates, and deletes
- automatic relationship syncing for nested objects and foreign keys
- export back into API-ready JSON
- reactive local reads for SwiftUI and UIKit

Core capabilities:
- import sync for full payloads or single items
- parent-scoped sync with explicit relationship paths
- export for root models and parent-scoped models
- reactive reads with `@SyncQuery`
- strict absent-key vs explicit-`null` semantics

SwiftSync is for teams already building on SwiftData who want:
- deterministic JSON -> local store sync
- export back into API-ready payloads
- reactive local reads for SwiftUI and UIKit
- explicit, testable backend semantics around missing vs `null`

## What SwiftSync Is

SwiftSync is not a backend, a database replacement, or an opinionated app architecture.

It is the missing sync layer between:
- a SwiftData model graph in your app
- a conventional JSON API on your backend

If your current pain is:
- repetitive mapping code
- fragile relationship updates
- unclear `null` vs missing semantics
- re-fetch/rebind boilerplate after mutations

that is exactly the problem SwiftSync is built to solve.

## Best Fit

SwiftSync is a strong fit when:
- you already want SwiftData to remain your local source of truth
- your backend returns normal resource payloads and relationship IDs
- you want explicit behavior around create, update, clear, and delete
- you want SwiftUI or UIKit screens to react to local data instead of mutation callbacks

## Not The Goal

SwiftSync is not trying to:
- replace SwiftData
- impose a server product or hosted platform
- hide backend contract details behind magic
- treat omission and `null` as the same thing

The design goal is boring, reliable sync behavior that fits naturally into an iOS app you already own.

## Install

Requirements:
- Xcode 17+
- Swift 6.2
- iOS 17+ / macOS 14+

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

## Quick Start

This is the shortest end-to-end path from model to live UI.

### 1. Define a syncable model

```swift
import SwiftData
import SwiftSync

@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var name: String
  var createdAt: Date?

  init(id: Int, name: String, createdAt: Date? = nil) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
  }
}
```

### 2. Create a `SyncContainer`

```swift
@MainActor
func makeSyncContainer() throws -> SyncContainer {
  try SyncContainer(
    for: User.self,
    keyStyle: .snakeCase
  )
}
```

### 3. Sync server JSON into SwiftData

```swift
let payload: [[String: Any]] = [
  [
    "id": 6,
    "name": "Shawn Merrill",
    "created_at": "2014-02-14T04:30:10+00:00"
  ]
]

try await syncContainer.sync(payload: payload, as: User.self)
```

### 4. Read it reactively in SwiftUI

```swift
import SwiftUI
import SwiftSync

struct UsersScreen: View {
  let syncContainer: SyncContainer

  @SyncQuery(
    User.self,
    in: syncContainer,
    sortBy: [SortDescriptor(\User.name)]
  )
  private var users: [User]

  var body: some View {
    List(users) { user in
      Text(user.name)
    }
  }
}
```

### 5. Export local state back to JSON

```swift
let rows = try syncContainer.export(as: User.self)
```

If this flow fits your app, the rest of the README covers relationship shapes, parent scope, reactive reads, and backend contract details.

## Table of Contents

- [Why SwiftSync](#why-swiftsync)
- [Demo App](#demo-app)
- [Install](#install)
- [Quick Start](#quick-start)
- [Migrating From Sync](docs/project/migrating-from-sync.md)
- [Property Mapping](#property-mapping)
- [Basic Example](#basic-example)
- [Reactive Reads](#reactive-reads)
- [Scenario -> Way of Use](#scenario---way-of-use)
- [Modeling and Mapping](#modeling-and-mapping)
- [Exporting JSON](#exporting-json)
- [Date Handling](#date-handling)
- [FAQ](docs/project/faq.md)
- [Backend Contract](docs/project/backend-contract.md)
- [API Reference](#api-reference)
- [License](#license)

## Why SwiftSync

Syncing JSON into a local store is repetitive:
- map attributes
- diff inserts/updates/deletes
- handle relationship updates
- avoid unnecessary writes

SwiftSync handles that core flow so app code can stay focused on domain behavior.

It is a strong fit when:
- your app already uses SwiftData
- your backend can follow stable `id`, `*_id`, and `*_ids` conventions
- you want strict missing-vs-`null` semantics instead of implicit magic
- you want the UI to read from local state while mutations sync through a service/domain layer

In practice, that means:
- less model-mapping boilerplate
- fewer relationship edge-case bugs
- one consistent import/export contract
- a UI that can stay local-first and reactive

Teams usually switch to SwiftSync when they want:
- one place to define JSON -> model mapping instead of per-endpoint glue code
- relationship updates to stop being hand-written and fragile
- local UI reads to stay stable while network mutations happen elsewhere
- payload semantics that make omission and clearing behave differently on purpose

Pain point -> outcome:
- repetitive mapping code -> convention-first syncing with explicit overrides only at API boundaries
- brittle relationship reconciliation -> built-in nested object and `*_id` / `*_ids` handling
- re-fetch/rebind churn after writes -> local-first reads through SwiftData and `@SyncQuery`
- ambiguous backend payload semantics -> strict absent-key means ignore, explicit `null` means clear/delete

## Demo App

The demo app lives in [Demo/Demo](/Users/nunez/code/ios/SwiftSync/Demo/Demo) and shows the intended workflow end to end:
- syncing backend-shaped project and task payloads into SwiftData
- reading that local state in SwiftUI screens
- editing tasks while keeping list and detail views in sync

Entry points:
- app setup: [DemoApp.swift](/Users/nunez/code/ios/SwiftSync/Demo/Demo/DemoApp.swift)
- main shell: [ContentView.swift](/Users/nunez/code/ios/SwiftSync/Demo/Demo/App/ContentView.swift)
- feature examples: [ProjectsView.swift](/Users/nunez/code/ios/SwiftSync/Demo/Demo/Features/Projects/ProjectsView.swift), [ProjectView.swift](/Users/nunez/code/ios/SwiftSync/Demo/Demo/Features/Projects/ProjectView.swift), [TaskView.swift](/Users/nunez/code/ios/SwiftSync/Demo/Demo/Features/TaskDetail/TaskView.swift)

## Property Mapping

Current defaults and behavior:
- convention-first mapping is expected
- inbound key style is configured once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional)
- acronym-aware snake mapping (`projectID` -> `project_id`, `remoteURL` -> `remote_url`)
- deep-path import/export is supported via `@RemoteKey("a.b.c")`
- scalar coercions are deterministic; relationship FK linking remains strict
- Demo models in this repo are convention-first, with explicit mapping only where backend keys intentionally differ (for example `description` -> `descriptionText`)

Practical usage rules:
- remove `@RemoteKey` when convention already matches (for example `projectID` maps to `project_id`)
- keep `@RemoteKey` when your local property name intentionally differs from the backend key (for example `descriptionText` -> `description`)
- configure inbound key style once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional)
- use `@RemoteKey("a.b.c")` for nested payload keys (import and export)

## Basic Example

### Model

![Relationship model example](Images/one-to-many-swift.png)

```swift
import SwiftData
import SwiftSync

@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var name: String
  var createdAt: Date?

  init(id: Int, name: String, createdAt: Date? = nil) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
  }
}
```

### JSON payload

```json
[
  {
    "id": 6,
    "name": "Shawn Merrill",
    "created_at": "2014-02-14T04:30:10+00:00"
  }
]
```

### Sync

```swift
try await SwiftSync.sync(payload: payload, as: User.self, in: context)
```

That single call will insert, update, and delete based on identity diffing.

You can also tune behavior per call:

```swift
try await SwiftSync.sync(
  payload: payload,
  as: User.self,
  in: context,
  relationshipOperations: .all
)
```

To update a single item without touching other rows, use `sync(item:)`:

```swift
try await SwiftSync.sync(
  item: taskDict,
  as: Task.self,
  in: context
)
```

## SyncContainer

`SyncContainer` is a thin SwiftData-based wrapper around `ModelContainer` that:
- exposes a shared `mainContext`
- creates background contexts for sync work
- observes background `ModelContext.didSave` and processes main-context pending changes
- configures inbound key style once (`.snakeCase` default, `.camelCase` optional)

```swift
let syncContainer = try await MainActor.run {
  try SyncContainer(
    for: User.self,
    keyStyle: .snakeCase, // default
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
  )
}

try await syncContainer.sync(payload: payload, as: User.self)
```

Behavior note:
- fresh fetches on `mainContext` see background saves
- retained object references may still need explicit UI rebind/requery

## Reactive Reads

SwiftUI is the primary integration path. Use `@SyncQuery` for list reads and `@SyncModel` for detail reads.

Sort order (ascending or mixed/descending):

```swift
@SyncQuery(
  Task.self,
  in: syncContainer,
  sortBy: [
    SortDescriptor(\Task.priority, order: .reverse),
    SortDescriptor(\Task.id)
  ]
)
var tasks: [Task]
```

Relationship-scoped query (to-one):

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

Relationship-scoped query (to-many):

```swift
@SyncQuery(
  Project.self,
  relationship: \.tasks,
  relationshipID: taskID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Project.id)]
)
var projectsContainingTask: [Project]
```

Keep using `predicate` when relationship-scoped `relationship/relationshipID` is not the right shape:
- screens that only have scalar IDs (no related model instance)
- non-parent filters (for example `assigneeID == userID`)
- compound business filters (for example status + date window + membership)

### UIKit / State Machines

SwiftUI is first class. For non-SwiftUI consumers:

- use `SyncQueryPublisher` for reactive lists
- use `SyncModelPublisher` for a single reactive row by sync ID

```swift
import Observation

final class ProjectsViewController: UIViewController {
  private var projectsObserver: SyncQueryPublisher<Project>?

  func bindProjects() {
    let observer = SyncQueryPublisher(
      Project.self,
      in: syncContainer,
      sortBy: [SortDescriptor(\Project.name)]
    )
    projectsObserver = observer

    func track() {
      withObservationTracking {
        applySnapshot(observer.rows)
      } onChange: {
        Task { @MainActor in track() }
      }
    }

    track()
  }
}
```

Relationship-scoped variant (to-one):

```swift
let publisher = SyncQueryPublisher(
  Task.self,
  relationship: \Task.assignee,
  relationshipID: userID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.title)]
)
```

Single-row variant:

```swift
let publisher = SyncModelPublisher(
  Task.self,
  id: taskID,
  in: syncContainer
)
```

Observe `publisher.row` the same way you would observe `publisher.rows`.

Both publishers reload automatically after relevant sync-driven saves, using the same internal invalidation mechanism as `@SyncQuery` / `@SyncModel`.

## Scenario -> Way of Use

### Scenario: payload only contains children for one parent

You have a user details screen, and the backend endpoint `/users/6/notes` returns only that user's notes. Each note comes without a `user_id`, because the endpoint itself is already scoped.

JSON:

```json
[
  {
    "id": 301,
    "text": "Call supplier before Friday"
  },
  {
    "id": 302,
    "text": "Prepare Q1 budget review"
  }
]
```

Model:

```swift
@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var name: String
}

@Syncable
@Model
final class Note {
  var id: Int
  var text: String
  @Relationship var user: User?
}

// Keep this extension when you want scoped identity by default for this model.
// `parentRelationship` provides the default parent scope relationship for this model.
extension Note: ParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Note, User?> { \.user }
}
```

Why `id` is not unique in this example:
- `ParentScopedModel` defaults to scoped identity (`(parent, id)` semantics).
- This allows the same remote child ID under different parents.
- If you add `@Attribute(.unique)` on `id`, SwiftData enforces global uniqueness and scoped duplicates cannot exist.

API:

```swift
let user = try context.fetch(FetchDescriptor<User>()).first { $0.id == 6 }!

try await SwiftSync.sync(
  payload: payload,
  as: Note.self,
  in: context,
  parent: user,
  relationship: \Note.user
)
```

Notes:
- This example keeps `ParentScopedModel`, so scoped identity is the default for `Note`.
- Parent-scoped sync requires an explicit `relationship:` key path.
- For models conforming to `ParentScopedModel`, the default identity policy remains scoped-by-parent.

### Scenario: to-one relationship by nested object

You have a list of employees, each employee has one company. The backend sends that company as an inline object in each employee row.

JSON:

```json
[
  {
    "id": 44,
    "full_name": "Ariana Patel",
    "company": {
      "id": 10,
      "name": "Apple"
    }
  }
]
```

Model:

```swift
@Syncable
@Model
final class Company {
  @Attribute(.unique) var id: Int
  var name: String
}

@Syncable
@Model
final class Employee {
  @Attribute(.unique) var id: Int
  var fullName: String
  var company: Company?
}
```

API:

```swift
try await SwiftSync.sync(payload: payload, as: Employee.self, in: context)
```

### Scenario: to-one relationship by `*_id`

You have employees and companies already synced. For employee updates, the backend sends only `company_id` instead of a nested company object.

JSON:

```json
[
  {
    "id": 44,
    "company_id": 10
  }
]
```

JSON to clear:

```json
[
  {
    "id": 44,
    "company_id": null
  }
]
```

Model:

```swift
@Syncable
@Model
final class Employee {
  @Attribute(.unique) var id: Int
  var company: Company?
}
```

API:

```swift
try await SwiftSync.sync(payload: payload, as: Employee.self, in: context)
```

### Scenario: to-many relationship by objects

You have chats and each chat has many messages. The backend sends each chat with an inline `messages` array.
SwiftSync treats to-many relationship updates as membership updates (unordered) in SwiftData.

JSON A:

```json
[
  {
    "id": 77,
    "title": "Launch Planning",
    "messages": [
      {
        "id": 101,
        "text": "Draft kickoff agenda"
      },
      {
        "id": 102,
        "text": "Share timeline v1"
      }
    ]
  }
]
```

JSON B:

```json
[
  {
    "id": 77,
    "title": "Launch Planning",
    "messages": [
      {
        "id": 102,
        "text": "Share timeline v2"
      },
      {
        "id": 103,
        "text": "Book design review"
      }
    ]
  }
]
```

Model:

```swift
@Syncable
@Model
final class Message {
  @Attribute(.unique) var id: Int
  var text: String
}

@Syncable
@Model
final class Chat {
  @Attribute(.unique) var id: Int
  var title: String
  var messages: [Message]
}
```

API:

```swift
try await SwiftSync.sync(payload: payload, as: Chat.self, in: context)
```

### Scenario: to-many relationship by `*_ids`

You already synced notes separately, and user payloads now include only `notes_ids` to define membership.
SwiftSync treats this as membership sync (unordered) and does not guarantee payload order persistence.

JSON A:

```json
[
  {
    "id": 6,
    "notes_ids": [301, 302]
  }
]
```

JSON B:

```json
[
  {
    "id": 6,
    "notes_ids": [302, 305]
  }
]
```

Model:

```swift
@Syncable
@Model
final class Note {
  @Attribute(.unique) var id: Int
}

@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var name: String
  var notes: [Note]
}
```

API:

```swift
try await SwiftSync.sync(payload: payload, as: User.self, in: context)
```

### Scenario: export local rows to API JSON

You have local SwiftData rows and need to send them to your backend in API format.

JSON output shape (default):

```json
[
  {
    "id": 1,
    "first_name": "Elvis",
    "last_name": "Nunez"
  }
]
```

Model:

```swift
@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var firstName: String
  var lastName: String
}
```

API:

```swift
let rows = try syncContainer.export(as: User.self)
```

## Modeling and Mapping

### `@Syncable`

`@Syncable` generates:
- `SyncUpdatableModel` conformance (make/apply + relationship sync)
- export support via `exportObject(keyStyle:dateFormatter:)`
Built-in relationship sync behavior:
- to-one by `*_id` (strict typed FK lookup)
- to-many by `*_ids` (unordered membership updates)
- nested to-one by relationship key (for example `company`)
- nested to-many by relationship key (for example `members`)

Identity selection order:
1. property marked with `@PrimaryKey` (or `@PrimaryKey(remote: ...)`)
2. `id`
3. `remoteID`

### Custom primary key

```swift
@Syncable
@Model
final class ExternalUser {
  @PrimaryKey
  @Attribute(.unique) var xid: String
  var name: String

  init(xid: String, name: String) {
    self.xid = xid
    self.name = name
  }
}
```

### Custom remote identity key

```swift
@Syncable
@Model
final class ExternalMappedUser {
  @PrimaryKey(remote: "external_id")
  @Attribute(.unique) var xid: String
  var name: String

  init(xid: String, name: String) {
    self.xid = xid
    self.name = name
  }
}
```

### Custom property mapping (import + export)

```swift
@Syncable
@Model
final class Account {
  @Attribute(.unique) var id: Int
  @RemoteKey("type") var userType: String
  @RemoteKey("profile.contact.email") var email: String?
  @NotExport var localOnly: String

  init(id: Int, userType: String, email: String?, localOnly: String) {
    self.id = id
    self.userType = userType
    self.email = email
    self.localOnly = localOnly
  }
}
```

Notes:
- `@RemoteKey` affects inbound sync mapping and export mapping.
- `@RemoteKey("a.b.c")` reads/writes nested payload paths.
- Deep paths are resolved from nested dictionaries and keep normal missing/null semantics.

## Exporting JSON

### Default

```swift
let rows = try syncContainer.export(as: User.self)
```

Defaults:
- snake_case keys
- relationships included as inline arrays/objects
- ISO-style UTC dates
- nils exported as `null`

To exclude a specific relationship from all exports, apply `@NotExport` to the property
in your model.

### Camel case

```swift
let syncContainer = SyncContainer(modelContainer, keyStyle: .camelCase)
let rows = try syncContainer.export(as: User.self)
```

### Parent-scoped export

```swift
let rows = try syncContainer.export(as: Note.self, parent: user)
```

## Date Handling

SwiftSync uses a custom high-performance inbound date parser (`SyncDateParser`).

Supported inputs:
- ISO8601 variants (`Z`, `+00:00`, `+0000`, no-timezone)
- date-only (`YYYY-MM-DD`)
- `YYYY-MM-DD HH:mm:ss`
- fractional seconds (deci/centi/milli/micro)
- unix timestamps (seconds and microseconds-like)

Invalid date behavior is best-effort and non-crashing.

our policy is honestly we do our best without affecting performance.

## API Reference

```swift
public final class SyncContainer {
  func sync<Model: SyncUpdatableModel>(
    payload: [Any],
    as model: Model.Type,
    relationshipOperations: SyncRelationshipOperations = .all
  ) async throws

  func sync<Model: SyncUpdatableModel>(
    item: [String: Any],
    as model: Model.Type,
    relationshipOperations: SyncRelationshipOperations = .all
  ) async throws

  func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
    payload: [Any],
    as model: Model.Type,
    parent: Parent,
    relationship: ReferenceWritableKeyPath<Model, Parent?>,
    relationshipOperations: SyncRelationshipOperations = .all
  ) async throws

  func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
    item: [String: Any],
    as model: Model.Type,
    parent: Parent,
    relationship: ReferenceWritableKeyPath<Model, Parent?>,
    relationshipOperations: SyncRelationshipOperations = .all
  ) async throws

  func export<Model: SyncUpdatableModel>(
    as model: Model.Type,
  ) throws -> [[String: Any]]

  func export<Model: SyncUpdatableModel & ParentScopedModel>(
    as model: Model.Type,
    parent: Model.SyncParent,
  ) throws -> [[String: Any]]
}

public enum SyncError: Error, Sendable, Equatable {
  case invalidPayload(model: String, reason: String)
  case cancelled
}

public struct SyncRelationshipOperations: OptionSet, Sendable {
  public static let insert: SyncRelationshipOperations
  public static let update: SyncRelationshipOperations
  public static let delete: SyncRelationshipOperations
  public static let all: SyncRelationshipOperations
}
```

## License

SwiftSync is released under the [MIT License](LICENSE).
