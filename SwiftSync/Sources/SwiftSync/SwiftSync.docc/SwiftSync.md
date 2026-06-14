# ``SwiftSync``

Keep SwiftData as the local source of truth while syncing conventional JSON APIs in and out, with explicit, predictable semantics.

## Overview

SwiftSync maps JSON payloads onto your SwiftData `@Model` types and back. Payload semantics are strict — an absent key is ignored (no mutation), while an explicit `null` clears the value — and key mapping is convention-based (snake_case ⇄ camelCase) with explicit overrides where you need them. Reads are reactive, so SwiftUI and UIKit update as the local store changes.

A typical integration is three steps:

1. **Define models once.** Annotate a SwiftData model with ``Syncable()`` (plus ``PrimaryKey(remote:)``, ``RemoteKey(_:)``, and ``NotExport()`` as needed) to synthesize its sync conformance.
2. **Sync in and out.** Wrap your `ModelContainer` in a ``SyncContainer`` and call its sync and export methods.
3. **Read reactively.** Use ``SyncQuery`` / ``SyncModel`` in SwiftUI, or ``SyncModelPublisher`` / ``SyncQueryPublisher`` in UIKit, to observe the local store.

```swift
@Syncable
@Model
final class Task {
    @PrimaryKey var id: String
    @RemoteKey("state.id") var stateID: String
    var title: String
    init(id: String, stateID: String, title: String) { … }
}

let container = SyncContainer(modelContainer)
try await container.sync(payload, as: Task.self)
```

## Topics

### Essentials

- ``SyncContainer``

### Defining Syncable Models

- ``Syncable()``
- ``PrimaryKey(remote:)``
- ``RemoteKey(_:)``
- ``NotExport()``
- ``SyncModelable``
- ``SyncUpdatableModel``
- ``ParentScopedModel``

### Payloads & Key Mapping

- ``SyncPayload``
- ``SyncPayloadConvertible``
- ``KeyStyle``

### Reactive Reads

- ``SyncQuery``
- ``SyncModel``
- ``SyncModelPublisher``
- ``SyncQueryPublisher``

### Relationships

- ``SyncRelationshipOperations``

### Data Freshness & Loading

- ``DataFreshnessPolicy``
- ``ScopeSyncStatus``

### Errors & Diagnostics

- ``SyncError``
- ``SyncContainer/SchemaValidationError``
- ``SyncContainer/ObjectiveCInitializationExceptionError``
