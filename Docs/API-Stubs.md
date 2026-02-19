# SwiftSync Milestone 1 API

This package ships a minimal but functional Milestone 1 inbound sync API.

## Modules

- `SwiftSyncCore`: sync model contracts, payload decoding, and typed errors.
- `SwiftSyncSwiftData`: `SwiftSync.sync`.
- `SwiftSyncMacros`: `@Syncable` macro that generates `SyncUpdatableModel` boilerplate.
- `SwiftSyncTesting`: mocked payload fixtures.

## Runtime behavior in this milestone

- `SwiftSync.sync`: applies source-of-truth payload diff sync (insert/update/delete) for models conforming to `SyncUpdatableModel`.
- Relationship-aware models can also conform to `SyncRelationshipUpdatableModel` to apply to-one/to-many updates in the same sync pass.

## Macro usage

```swift
import SwiftSyncMacros

@Syncable
@Model
final class DemoUser { ... }
```

Custom primary key:

```swift
@Syncable
@Model
final class ExternalUser {
    @PrimaryKey
    @Attribute(.unique) var xid: String
    var name: String
}
```

Remote key mapping:

```swift
@Syncable
@Model
final class ExternalMappedUser {
    @PrimaryKey(remote: "external_id")
    @Attribute(.unique) var xid: String
    var name: String
}
```

## Stable signatures

```swift
public extension SwiftSync {
    static func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext
    ) async throws
}
```

## Validation

```bash
swift test
```
