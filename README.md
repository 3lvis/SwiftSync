# SwiftSync

SwiftSync syncs JSON into SwiftData and exports SwiftData back to JSON using a convention-first model.

## Install

Add the package and import:

```swift
import SwiftSync
```

## Core behavior

- `sync(payload:as:)` inserts, updates, and deletes rows by identity.
- `sync(item:as:)` updates/inserts one row (no collection-level delete diff).
- Parent-scoped sync requires an explicit `relationship:` key path.
- Missing keys are ignored; explicit `null` applies clear/reset semantics.
- Relationship operations are controlled with `SyncRelationshipOperations` (`.insert`, `.update`, `.delete`, `.all`).

## Quick example

```swift
import SwiftData
import SwiftSync

@Syncable
@Model
final class User {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

let syncContainer = try SyncContainer(
    for: User.self,
    keyStyle: .snakeCase,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
)

try await syncContainer.sync(
    payload: [["id": 1, "name": "Ava"]],
    as: User.self
)
```

## Mapping and keys

- Container-level input key style is `KeyStyle.snakeCase` by default (`.camelCase` is optional).
- Convention mapping is preferred.
- Use `@RemoteKey("...")` only when backend keys intentionally differ.
- Deep paths are supported for import/export (`@RemoteKey("profile.contact.email")`).

## Reactive reads

SwiftUI wrappers:

- `@SyncQuery` for list reads.
- `@SyncModel` for single-row reads by identity.

UIKit/non-wrapper usage:

- `SyncQueryPublisher` provides the same query shapes as `@SyncQuery`.

Relationship-scoped query example:

```swift
@SyncQuery(
    Task.self,
    relationship: \Task.project,
    relationshipID: projectID,
    in: syncContainer,
    sortBy: [SortDescriptor(\Task.id)]
)
var tasks: [Task]
```

## Export

```swift
let rows = try syncContainer.export(as: User.self)
```

Defaults:

- key style follows container `keyStyle`
- relationships are exported inline
- dates use `yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX` in UTC

## API surface (current)

- `SyncContainer` (sync + export entry point)
- `@Syncable`, `@PrimaryKey`, `@RemoteKey`, `@NotExport`
- `SyncPayloadConvertible` overloads for typed payload wrappers
- `SyncError` (`.invalidPayload`, `.cancelled`)
- `SyncRelationshipOperations`

## Docs index

- `docs/project/property-mapping-contract.md`
- `docs/project/parent-scope.md`
- `docs/project/reactive-reads.md`
- `docs/project/backend-contract.md`
- `docs/project/faq.md`
