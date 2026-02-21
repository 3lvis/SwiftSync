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
- [Basic Example](#basic-example)
- [Reactive Reads (SwiftUI)](#reactive-reads-swiftui)
- [Scenario -> Way of Use](#scenario---way-of-use)
- [Modeling and Mapping](#modeling-and-mapping)
- [Exporting JSON](#exporting-json)
- [Date Handling](#date-handling)
- [FAQ](#faq)
- [Advanced FAQ](docs/faq.md)
- [API Reference](#api-reference)

## Why SwiftSync

Syncing JSON into a local store is repetitive:
- map attributes
- diff inserts/updates/deletes
- handle relationship updates
- avoid unnecessary writes

SwiftSync handles that core flow so app code can stay focused on domain behavior.

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

```swift
let syncContainer = try await MainActor.run {
  try SyncContainer(
    for: User.self,
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

extension Note: ParentScopedModel {
  typealias SyncParent = User
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
- `ExportModel` and `SyncQuerySortableModel` conformance

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

If you need global behavior on a parent-scoped model, override it:

```swift
extension Note {
  static var syncIdentityPolicy: SyncIdentityPolicy { .global }
}
```

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

### Custom export mapping

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

## FAQ

### Do I have to import multiple modules?

No. Use only:

```swift
import SwiftSync
```

### What if payload has duplicate items with the same identity?

SwiftSync applies payload rows in order. If the same identity appears more than once, later rows win.

### What if local DB already has duplicate rows for the same primary key?

SwiftSync deduplicates local identity collisions during sync and keeps one logical row per identity.

### What if a row has missing or null primary key?

That row is skipped for matching/diffing. Sync continues for valid rows.

### What happens when payload value is `null`?

- optional scalar -> `nil`
- non-optional primitive scalar -> default value (`""`, `0`, `false`, epoch date, zero UUID)

### Does relationship sync happen automatically for complex graphs?

`@Syncable` now auto-generates relationship helper logic for the common FK patterns:
- to-one by `*_id` (strict typed FK lookup)
- to-many by `*_ids` (unordered membership updates)
- nested relationship objects by relationship key (`company`, `members`, etc.)

No wrapper extension is needed when using `@Syncable`.

For custom domain merge policies, implement custom `applyRelationships(...)`.

### Does SwiftSync support ordered to-many relationship syncing?

Not currently.

- SwiftData does not expose Core Data-style ordered relationship metadata for this use case.
- SwiftSync currently treats to-many relationship sync as unordered membership.
- If you need deterministic UI order, store an explicit scalar order field (for example `position`) and query with `sortBy`.

### Can two different parents have children with the same `id`?

Yes, by default for `ParentScopedModel`.

- Default identity policy is `.scopedByParent`.
- Scoped sync diff/delete stays inside that parent scope.
- If the child model has `@Attribute(.unique)` on raw `id`, SwiftData global uniqueness wins and duplicates across parents are not possible.

### How strict is foreign-key (`*_id`) relationship linking?

Relationship FK linking is strict by type.

- `company_id: 10` links to `Int` identity `10`.
- `company_id: "10"` does not coerce to `Int` for relationship linking.
- Scalar attribute coercions are still supported for non-relationship fields.

### Can I control relationship insert/update/delete work per sync call?

Yes. Use `relationshipOperations`:

```swift
try await SwiftSync.sync(
  payload: payload,
  as: Employee.self,
  in: context,
  relationshipOperations: [.insert, .update]
)
```

### What happens if two sync calls run at the same time?

SwiftSync serializes sync calls per store/container.

- Calls targeting the same `ModelContainer` are queued (no overlap/interleaving).
- Final state is last-writer-wins by queued execution order.
- Calls targeting different stores can run concurrently.

### How do I cancel a sync?

Use Swift Concurrency task cancellation:

```swift
let task = Task {
  try await SwiftSync.sync(payload: payload, as: User.self, in: context)
}

task.cancel()

do {
  try await task.value
} catch SyncError.cancelled {
  // expected cooperative cancellation
}
```

Cancellation is cooperative. SwiftSync rolls back unsaved in-memory changes for that run, but it does not roll back work that was already saved earlier.

### Can I still control sort direction with `@SyncQuery`?

Yes. Use explicit `SortDescriptor` values when you need direction:

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

### When should I use `sortBy: [\.field]` vs `sortBy: [SortDescriptor(...)]`?

- Use `sortBy: [\.field]` for concise default ascending sort.
- Use `sortBy: [SortDescriptor(...)]` for descending or mixed ordering.
- If your model is not `@Syncable`, shorthand requires `SyncQuerySortableModel` conformance; explicit `SortDescriptor` works directly.

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
