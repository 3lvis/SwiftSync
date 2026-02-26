# SwiftSync

SwiftSync makes syncing JSON with SwiftData feel obvious.

You define models once, then use one API to:
- sync server payloads into local SwiftData
- export local SwiftData back into API-ready JSON

It follows convention over configuration and keeps behavior deterministic.

## Install

Add the package to your project and import:

```swift
import SwiftSync
```

## Table of Contents

- [Why SwiftSync](#why-swiftsync)
- [Property Mapping](#property-mapping)
- [Basic Example](#basic-example)
- [Reactive Reads (SwiftUI)](#reactive-reads-swiftui)
- [Scenario -> Way of Use](#scenario---way-of-use)
- [Modeling and Mapping](#modeling-and-mapping)
- [Exporting JSON](#exporting-json)
- [Date Handling](#date-handling)
- [FAQ](docs/project/faq.md)
- [Backend Contract](docs/project/backend-contract.md)
- [API Reference](#api-reference)

## Why SwiftSync

Syncing JSON into a local store is repetitive:
- map attributes
- diff inserts/updates/deletes
- handle relationship updates
- avoid unnecessary writes

SwiftSync handles that core flow so app code can stay focused on domain behavior.

## Property Mapping

Current defaults and behavior:
- convention-first mapping is expected
- inbound key style is configured once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional)
- acronym-aware snake mapping (`projectID` -> `project_id`, `remoteURL` -> `remote_url`)
- deep-path import/export is supported via `@RemotePath("a.b.c")`
- scalar coercions are deterministic; relationship FK linking remains strict
- Demo models in this repo are convention-first, with explicit mapping only where backend keys intentionally differ (for example `description` -> `descriptionText`)

Practical usage rules:
- remove `@RemoteKey` when convention already matches (for example `projectID` maps to `project_id`)
- keep `@RemoteKey` when your local property name intentionally differs from the backend key (for example `descriptionText` -> `description`)
- configure inbound key style once at `SyncContainer` (`.snakeCase` default, `.camelCase` optional)
- use `@RemotePath("a.b.c")` for nested payload keys (import and export)

## Basic Example

### Model

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
  missingRowPolicy: .delete,
  relationshipOperations: .all
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
    inputKeyStyle: .snakeCase, // default
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
  )
}

let background = syncContainer.makeBackgroundContext()
try await SwiftSync.sync(payload: payload, as: User.self, in: background)
```

Behavior note:
- fresh fetches on `mainContext` see background saves
- retained object references may still need explicit UI rebind/requery

## Reactive Reads (SwiftUI)

Use `@SyncQuery` for list reads and `@SyncModel` for detail reads.

Shorthand ascending sort:

```swift
@SyncQuery(
  User.self,
  in: syncContainer,
  sortBy: [\.displayName, \.id]
)
var users: [User]
```

Descending or mixed sort order:

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

To-one query shorthand (ownership / belongs-to):

```swift
@SyncQuery(
  Task.self,
  toOne: project,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.id)]
)
var tasks: [Task]
```

If to-one inference is ambiguous, pass the relationship explicitly:

```swift
@SyncQuery(
  Ticket.self,
  toOne: user,
  via: \.assignee,
  in: syncContainer,
  sortBy: [SortDescriptor(\Ticket.id)]
)
var assignedTickets: [Ticket]
```

Keep using `predicate` when `toOne:` is not the right shape:
- screens that only have scalar IDs (no related model instance)
- non-parent filters (for example `assigneeID == userID`)
- compound business filters (for example status + date window + membership)

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
// `parentRelationship` is required only for ambiguous parent mappings.
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
  parent: user
)
```

Notes:
- This example keeps `ParentScopedModel`, so scoped identity is the default for `Note`.
- Parent relationship inference is the default behavior for parent sync.
- If `Note` has exactly one to-one relationship to `User`, `parentRelationship` is inferred.
- `parentRelationship` is only required when there are multiple candidate relationships to the same parent type.
- If there are zero candidates, sync fails because the requested parent scope cannot be resolved for that model.
- `identityPolicy` defaults to `.global` for inferred parent sync. Use `.scopedByParent` when duplicate child IDs across different parents are valid.
- Inferred scoped example: `try await SwiftSync.sync(payload: payload, as: Note.self, in: context, parent: user, identityPolicy: .scopedByParent)`

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
let rows = try SwiftSync.export(as: User.self, in: context)
```

## Modeling and Mapping

### `@Syncable`

`@Syncable` generates:
- `SyncUpdatableModel` conformance (make/apply)
- `SyncRelationshipUpdatableModel` conformance (auto relationship sync)
- `ExportModel` conformance
- `syncSortDescriptor(for:)` implementation for `SyncModelable` sort sugar

Built-in relationship sync behavior:
- to-one by `*_id` (strict typed FK lookup)
- to-many by `*_ids` (unordered membership updates)
- nested to-one by relationship key (for example `company`)
- nested to-many by relationship key (for example `members`)

Identity selection order:
1. property marked with `@PrimaryKey` (or `@PrimaryKey(remote: ...)`)
2. `id`
3. `remoteID`

### Identity policy (global vs parent-scoped)

`SyncModelable` supports two identity policies:
- `.global`: one row per identity for the whole store.
- `.scopedByParent`: identity is scoped to the parent for `ParentScopedModel`.

Defaults:
- `SyncUpdatableModel` -> `.global`
- `ParentScopedModel` -> `.scopedByParent`
- inferred parent sync (`sync(... parent: Parent)`) -> `.global` unless you pass `identityPolicy: .scopedByParent`

If you need global behavior on a parent-scoped model, override it:

```swift
extension Note: GlobalParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Note, User?> { \.user }
}
```

`GlobalParentScopedModel` is just a convenience protocol that sets
`syncIdentityPolicy = .global` for `ParentScopedModel`.

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
  @RemotePath("profile.contact.email") var email: String?
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
- `@RemoteKey` and `@RemotePath` affect inbound sync mapping and export mapping.
- `@RemotePath("a.b.c")` reads/writes nested payload paths.
- Deep paths are resolved from nested dictionaries and keep normal missing/null semantics.

## Exporting JSON

### Default

```swift
let rows = try SwiftSync.export(as: User.self, in: context)
```

Defaults:
- snake_case keys
- relationships included in array mode
- ISO-style UTC dates
- nils exported as `null`

### Camel case

```swift
let rows = try SwiftSync.export(as: User.self, in: context, using: .camelCase)
```

### Exclude relationships

```swift
let rows = try SwiftSync.export(as: User.self, in: context, using: .excludedRelationships)
```

### Nested relationship export (`*_attributes`)

```swift
var options = ExportOptions()
options.relationshipMode = .nested
let rows = try SwiftSync.export(as: User.self, in: context, using: options)
```

### Parent-scoped export

```swift
let rows = try SwiftSync.export(as: Note.self, in: context, parent: user)
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
public enum SwiftSync {}

public extension SwiftSync {
  static func sync<Model: SyncUpdatableModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    missingRowPolicy: SyncMissingRowPolicy = .delete,
    relationshipOperations: SyncRelationshipOperations = .all
  ) async throws

  static func sync<Model: ParentScopedModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    parent: Model.SyncParent,
    missingRowPolicy: SyncMissingRowPolicy = .delete,
    relationshipOperations: SyncRelationshipOperations = .all
  ) async throws

  static func sync<Model: SyncUpdatableModel, Parent: PersistentModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    parent: Parent,
    identityPolicy: SyncIdentityPolicy = .global,
    missingRowPolicy: SyncMissingRowPolicy = .delete,
    relationshipOperations: SyncRelationshipOperations = .all
  ) async throws

  static func export<Model: ExportModel>(
    as model: Model.Type,
    in context: ModelContext,
    using options: ExportOptions = ExportOptions()
  ) throws -> [[String: Any]]

  static func export<Model: ExportModel & ParentScopedModel>(
    as model: Model.Type,
    in context: ModelContext,
    parent: Model.SyncParent,
    using options: ExportOptions = ExportOptions()
  ) throws -> [[String: Any]]
}

public enum SyncError: Error, Sendable, Equatable {
  case invalidPayload(model: String, reason: String)
  case cancelled
}

public enum SyncMissingRowPolicy: Sendable {
  case delete
  case keep
}

public struct SyncRelationshipOperations: OptionSet, Sendable {
  public static let insert: SyncRelationshipOperations
  public static let update: SyncRelationshipOperations
  public static let delete: SyncRelationshipOperations
  public static let all: SyncRelationshipOperations
}

public enum SyncIdentityPolicy: Sendable {
  case global
  case scopedByParent
}
```
