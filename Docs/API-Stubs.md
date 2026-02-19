# Current API

This package ships inbound sync plus outbound export.

## Modules

- `Core`: sync/export contracts, payload decoding, date parsing, and typed errors.
- `SwiftDataBridge`: `SwiftSync.sync` and `SwiftSync.export`.
- `Macros`: `@Syncable` macro that generates sync/export boilerplate.
- `TestingKit`: mocked payload fixtures.

## Behavior

- `SwiftSync.sync`: applies source-of-truth payload diff sync (insert/update/delete) for models conforming to `SyncUpdatableModel`.
- Relationship-aware models can also conform to `SyncRelationshipUpdatableModel` to apply to-one/to-many updates in the same sync pass.
- Parent-scoped child sync is available for `ParentScopedModel` via `SwiftSync.sync(..., parent:)`.
- `SwiftSync.export`: exports model rows to JSON dictionaries with configurable key style, relationship mode, date formatting, and null handling.

## Macro usage

```swift
import Macros

@Syncable
@Model
final class DemoUser { ... }
```

Export mapping controls:

```swift
@Syncable
@Model
final class DemoUser {
    @Attribute(.unique) var id: Int
    @RemoteKey("type") var userType: String
    @RemotePath("profile.contact.email") var email: String?
    @NotExport var localOnly: String
}
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

    static func sync<Model: ParentScopedModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext,
        parent: Model.SyncParent
    ) async throws

    static func export<Model: ExportModel>(
        as model: Model.Type,
        in context: ModelContext,
        using options: ExportOptions
    ) throws -> [[String: Any]]

    static func export<Model: ExportModel & ParentScopedModel>(
        as model: Model.Type,
        in context: ModelContext,
        parent: Model.SyncParent,
        using options: ExportOptions
    ) throws -> [[String: Any]]
}
```

## Validation

```bash
swift test
```
