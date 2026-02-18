# SwiftSync Milestone 1 API

This package ships a minimal but functional Milestone 1 inbound sync API.

## Modules

- `SwiftSyncCore`: schema and sync option primitives.
- `SwiftSyncSwiftData`: `SwiftSync.sync` and `ModelContext.sync`.
- `SwiftSyncMacros`: `@Syncable` macro that generates `SyncUpdatableModel` boilerplate.
- `SwiftSyncTesting`: mocked payload fixtures.

## Runtime behavior in this milestone

- `SwiftSync.sync`: applies flat-model upserts for models conforming to `SyncUpdatableModel`.

## Macro usage

```swift
import SwiftSyncMacros

@Syncable
@Model
final class DemoUser { ... }
```

## Stable signatures

```swift
public extension SwiftSync {
    static func sync<Model: SyncUpdatableModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext,
        options: SyncOptions = .init()
    ) async throws
}

public extension ModelContext {
    func sync<Model: SyncUpdatableModel>(
        _ payload: [Any],
        as model: Model.Type,
        options: SyncOptions = .init()
    ) async throws
}
```

## Demo

```bash
swift run SwiftSyncDemo
```
