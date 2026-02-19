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
- [Scenario -> Way of Use](#scenario---way-of-use)
- [Modeling and Mapping](#modeling-and-mapping)
- [Exporting JSON](#exporting-json)
- [Date Handling](#date-handling)
- [FAQ](#faq)
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

## Scenario -> Way of Use

### Scenario: payload only contains children for one parent

When to use:
- You call an endpoint like `/users/6/notes` and it only returns that user’s notes.
- Payload does not include parent IDs in each child row.

Expected result:
- Incoming notes are linked to the provided parent.
- Missing notes for that parent are removed.
- Notes for other parents are untouched.

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
  @Attribute(.unique) var id: Int
  var text: String
  @Relationship var user: User?
}

extension Note: ParentScopedModel {
  typealias SyncParent = User
  static var parentRelationship: ReferenceWritableKeyPath<Note, User?> { \.user }
}
```

JSON:

```json
[
  { "id": 301, "text": "Call supplier before Friday" },
  { "id": 302, "text": "Prepare Q1 budget review" }
]
```

API call:

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

When to use:
- Backend sends the related object inline (for example `company` nested inside user/employee).

Expected result:
- Related object is upserted.
- To-one link points to that related object.

Model:

```swift
@Syncable
@Model
final class Company { @Attribute(.unique) var id: Int; var name: String }

@Syncable
@Model
final class Employee {
  @Attribute(.unique) var id: Int
  var fullName: String
  var company: Company?
}
```

JSON:

```json
[
  {
    "id": 44,
    "full_name": "Ariana Patel",
    "company": { "id": 10, "name": "Apple" }
  }
]
```

API call:

```swift
try await SwiftSync.sync(payload: payload, as: Employee.self, in: context)
```

### Scenario: to-one relationship by `*_id`

When to use:
- Backend sends only foreign key IDs for a to-one relation.

Expected result:
- Non-null ID links relation if target exists.
- `null` clears the relation.
- Missing key keeps current relation unchanged.

Model:

```swift
@Syncable
@Model
final class Employee { @Attribute(.unique) var id: Int; var company: Company? }
```

JSON:

```json
[
  { "id": 44, "company_id": 10 }
]
```

JSON to clear:

```json
[
  { "id": 44, "company_id": null }
]
```

API call:

```swift
try await SwiftSync.sync(payload: payload, as: Employee.self, in: context)
```

### Scenario: to-many relationship by objects

When to use:
- Backend sends full related objects in an array.

Expected result:
- Membership is replaced by payload membership.
- Existing children update in place.
- Removed IDs are no longer related.

Model:

```swift
@Syncable
@Model
final class Message { @Attribute(.unique) var id: Int; var text: String }

@Syncable
@Model
final class Chat {
  @Attribute(.unique) var id: Int
  var title: String
  var messages: [Message]
}
```

JSON A:

```json
[
  {
    "id": 77,
    "title": "Launch Planning",
    "messages": [
      { "id": 101, "text": "Draft kickoff agenda" },
      { "id": 102, "text": "Share timeline v1" }
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
      { "id": 102, "text": "Share timeline v2" },
      { "id": 103, "text": "Book design review" }
    ]
  }
]
```

API call:

```swift
try await SwiftSync.sync(payload: payload, as: Chat.self, in: context)
```

### Scenario: to-many relationship by `*_ids`

When to use:
- Backend sends only IDs for related objects and those rows already exist (or are synced elsewhere).

Expected result:
- Relationship membership matches exactly the provided ID list.
- Re-running same payload is idempotent.

Model:

```swift
@Syncable
@Model
final class Note { @Attribute(.unique) var id: Int }

@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var name: String
  var notes: [Note]
}
```

JSON A:

```json
[
  { "id": 6, "notes_ids": [301, 302] }
]
```

JSON B:

```json
[
  { "id": 6, "notes_ids": [302, 305] }
]
```

API call:

```swift
try await SwiftSync.sync(payload: payload, as: User.self, in: context)
```

### Scenario: export local rows to API JSON

When to use:
- You need outbound JSON for create/update requests.

Expected result:
- Keys are transformed per export options.
- Dates and scalars are encoded to JSON-friendly values.
- Relationships are included/excluded based on export mode.

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

JSON output shape (default):

```json
[
  { "id": 1, "first_name": "Elvis", "last_name": "Nunez" }
]
```

API call:

```swift
let rows = try SwiftSync.export(as: User.self, in: context)
```

## Modeling and Mapping

### `@Syncable`

`@Syncable` generates sync and export boilerplate for flat attributes.

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

Flat attributes are automatic with `@Syncable`.
For relationship behavior, implement `SyncRelationshipUpdatableModel` and define `applyRelationships(...)`.

## API Reference

```swift
public enum SwiftSync {}

public extension SwiftSync {
  static func sync<Model: SyncUpdatableModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext
  ) async throws

  static func sync<Model: ParentScopedModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    parent: Model.SyncParent
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
```
