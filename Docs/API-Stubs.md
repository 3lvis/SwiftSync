# SwiftSync Milestone 0 API Stubs

This package ships a minimal API for `0.1.0-alpha`.

## Modules

- `SwiftSyncCore`: schema and sync option primitives.
- `SwiftSyncSwiftData`: `SwiftSync.sync` and `ModelContext.sync`.
- `SwiftSyncTesting`: mocked payload fixtures.

## Runtime behavior in this milestone

- `SwiftSync.sync`: no-op stub that validates API wiring and returns when successful.

## Stable signatures

```swift
public extension SwiftSync {
    static func sync<Model: PersistentModel>(
        payload: [Any],
        as model: Model.Type,
        in context: ModelContext,
        options: SyncOptions = .init()
    ) async throws
}

public extension ModelContext {
    func sync<Model: PersistentModel>(
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
