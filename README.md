![SwiftSync](Images/logo-v3.png)

SwiftSync is a sync layer for SwiftData apps.

You define models once, read from local SwiftData, and let SwiftSync handle the repetitive JSON sync/export work in between.

Features:

- Convention-first JSON -> SwiftData mapping
- Deterministic diffing for inserts, updates, and deletes
- Automatic relationship syncing for nested objects and foreign keys
- Export back into API-ready JSON
- Reactive local reads for SwiftUI and UIKit

## Quick Start

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

If this fits your app, continue with the full overview.

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

Table of contents:

- [Why SwiftSync](#why-swiftsync)
- [Demo App](#demo-app)
- [Property Mapping](#property-mapping)
- [Reactive Reads](#reactive-reads)
- [Supported Payload Shapes](#supported-payload-shapes)
- [Modeling and Mapping](#modeling-and-mapping)
- [Exporting JSON](#exporting-json)
- [Date Handling](#date-handling)
- [Further Reading](#further-reading)
- [License](#license)

## Why SwiftSync

Syncing API payloads into a local store usually means repeating the same work in every app:

- map JSON keys onto local properties
- reconcile inserts, updates, and deletions
- keep relationships correct when the payload shape changes
- make local UI reads stay coherent after background sync work

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

- convention-first mapping is expected
- inbound key style is configured once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional)
- acronym-aware snake mapping (`projectID` -> `project_id`, `remoteURL` -> `remote_url`)
- deep-path import/export is supported via `@RemoteKey("a.b.c")`
- scalar coercions are deterministic; relationship FK linking remains strict
- remove `@RemoteKey` when convention already matches (for example `projectID` maps to `project_id`)
- keep `@RemoteKey` when your local property name intentionally differs from the backend key (for example `descriptionText` -> `description`)
- use `@RemoteKey("a.b.c")` for nested payload keys (import and export)

## Reactive Reads

Use `@SyncQuery` for list reads and `@SyncModel` for detail reads.

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

## Supported Payload Shapes

SwiftSync supports the shapes most JSON APIs actually send:

- root collections for insert/update/delete diffing
- single-item updates with `sync(item:)`
- to-one relationships as nested objects or `*_id`
- to-many relationships as nested arrays or `*_ids`
- parent-scoped sync when an endpoint only returns children for one parent
- export back to API-ready JSON

Relationship shape example:

![Relationship model example](Images/one-to-many-swift.png)

That same model can be synced from nested objects:

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

Or from relationship IDs when the children already exist:

```json
[
  {
    "id": 6,
    "notes_ids": [301, 302]
  }
]
```

Parent-scoped sync requires an explicit `relationship:` key path:

```swift
try await SwiftSync.sync(
  payload: payload,
  as: Note.self,
  in: context,
  parent: user,
  relationship: \Note.user
)
```

## Modeling and Mapping

### `@Syncable`

`@Syncable` generates:

- `SyncUpdatableModel` conformance (make/apply + relationship sync)
- export support via `exportObject(keyStyle:dateFormatter:)`

It supports:

- to-one by `*_id` (strict typed FK lookup)
- to-many by `*_ids` (unordered membership updates)
- nested to-one by relationship key (for example `company`)
- nested to-many by relationship key (for example `members`)

Identity selection order:

1. property marked with `@PrimaryKey` (or `@PrimaryKey(remote: ...)`)
2. `id`
3. `remoteID`

For customization:

- use `@PrimaryKey` when identity is not `id`
- use `@PrimaryKey(remote: "external_id")` when the remote identity key differs
- use `@RemoteKey` when your local property name intentionally differs from the payload

Combined example:

```swift
@Syncable
@Model
final class ExternalAccount {
  @PrimaryKey(remote: "external_id")
  @Attribute(.unique) var xid: String
  @RemoteKey("type") var accountType: String
  @RemoteKey("profile.contact.email") var email: String?
  @NotExport var localOnly: String

  init(xid: String, accountType: String, email: String?, localOnly: String) {
    self.xid = xid
    self.accountType = accountType
    self.email = email
    self.localOnly = localOnly
  }
}
```

Notes:

- `@RemoteKey` affects inbound sync mapping and export mapping.
- `@RemoteKey("a.b.c")` reads/writes nested payload paths.
- Deep paths preserve normal missing/null semantics.

## Exporting JSON

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
let rows = try syncContainer.export(as: Note.self, parent: user)
```

## Date Handling

Inbound date parsing supports common ISO8601 variants, date-only strings, `YYYY-MM-DD HH:mm:ss`, fractional seconds, and unix timestamps.
If your backend sends normal app dates, SwiftSync is built to accept them without extra formatter plumbing.

## Further Reading

- [Migrating From Sync](docs/project/migrating-from-sync.md)
- [Reactive Reads](docs/project/reactive-reads.md)
- [Backend Contract](docs/project/backend-contract.md)
- [FAQ](docs/project/faq.md)

## License

SwiftSync is released under the [MIT License](LICENSE).
