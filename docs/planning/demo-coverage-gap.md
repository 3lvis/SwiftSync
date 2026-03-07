# Demo Coverage Gap — Public SwiftSync API Not Covered by Demo

**Purpose:** Track only public SwiftSync API surface that is not exercised by Demo runtime code.

**Scope rule:** Coverage here is based on call sites/usages in `Demo/Demo/**` runtime code. `DemoTests` and `SwiftSync` test targets are excluded.

## Open items

### Public macros not exercised in demo models

- [ ] Exercise `@PrimaryKey(remote:)` in a demo model.
- [ ] Exercise `@RemotePath(_:)` in a demo model.

### Public `SyncContainer` members not exercised by demo runtime

- [ ] Exercise `SyncContainer.init(_ modelContainer:keyStyle:dateFormatter:)`.
- [ ] Exercise `SyncContainer.makeBackgroundContext()`.
- [ ] Exercise `SyncContainer.sync(item:as:parent:relationshipOperations:)`.

### Public reactive query API overloads not exercised by demo runtime

- [ ] Exercise `SyncQuery.init(_:in:sortBy:animation:)` (no `relatedTo`, no `predicate`).
- [ ] Exercise `SyncQuery.init(_:predicate:in:sortBy:animation:)`.
- [ ] Exercise `SyncQuery.init(_:relatedTo:relatedID:through:in:sortBy:animation:)` (to-one explicit path).
- [ ] Exercise `SyncQuery.init(_:relatedTo:relatedID:through:in:sortBy:animation:)` (to-many explicit path).

### Public `SyncQueryPublisher` API not exercised by demo runtime

- [ ] Exercise `SyncQueryPublisher.rowsPublisher`.
- [ ] Exercise `SyncQueryPublisher.init(_:predicate:in:sortBy:)`.
- [ ] Exercise `SyncQueryPublisher.init(_:relatedTo:relatedID:through:in:sortBy:)` (to-one explicit path).
- [ ] Exercise `SyncQueryPublisher.init(_:relatedTo:relatedID:through:in:sortBy:)` (to-many explicit path).

### Public export configuration API not exercised explicitly by demo runtime

- [ ] Exercise non-default `KeyStyle` (`.camelCase`) through demo runtime.
- [ ] Exercise non-default `ExportOptions` date formatter through demo runtime.

### Public protocol-level API not exercised directly by demo runtime call sites

- [ ] Exercise direct `SyncPayload` API usage (`contains`, `value`, `required`) from demo runtime code.
- [ ] Exercise direct `SyncError` handling from demo runtime code.
