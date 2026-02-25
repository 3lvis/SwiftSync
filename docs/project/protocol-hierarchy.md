# Protocol Hierarchy — What It Is and Whether You Need It

## Why the Demo Doesn't Use Any Protocol Directly

The demo uses `@Syncable` on every model. `@Syncable` is a macro that generates conformances to all the protocols automatically. From the user side, the protocols are invisible — they only exist so the *engine* can make type-safe generic calls.

The protocols are the vocabulary the engine speaks internally. You never write them; the macro writes them for you.

---

## What Each Protocol Actually Does

### `SyncModelable` — identity

The base of everything. Provides:
- `SyncID` (the type of your primary key, e.g. `Int` or `String`)
- `syncIdentity` (keypath to the primary key field, e.g. `\.id`)
- `syncIdentityRemoteKeys` (what JSON keys map to the identity, e.g. `["id"]`)
- `syncDefaultRefreshModelTypes` (which model types a reactive query should refresh when this model changes)

**Used by:** the reactive query system (`SyncQuery`, `SyncModel`) to match rows by ID after a sync. Without identity, SwiftSync cannot tell "did this row already exist?" or "which row is the one to update?".

### `SyncUpdatableModel` — create and update

Adds two methods:
- `make(from:)` — create a new model instance from a payload dict
- `apply(_:)` — update an existing instance from a payload dict

**Used by:** `SwiftSync.sync()`. This is the constraint that makes `sync(payload:as:)` compile — the model must know how to build and update itself.

### `SyncRelationshipUpdatableModel` — relationship wiring

Adds one method: `applyRelationships(_:in:operations:)`. After a model row is saved, this is called to resolve foreign-key references (e.g. set `task.project = <fetched Project>`).

**Used by:** the sync engine, but via a *runtime cast*, not a static constraint. The engine does `row as? any SyncRelationshipUpdatableModel` at runtime so the sync entry point only needs `SyncUpdatableModel` in its signature.

### `SyncQuerySortableModel` — query sorting

Adds one method: `syncSortDescriptor(for:)`. Translates a keypath on the model to a SwiftData `SortDescriptor`.

**Used by:** `SyncQuery` — the reactive query wrapper. Provides overloads that accept keypaths for sorting. If your query system dropped keypath-based sort sugar, this protocol could go away.

### `ParentScopedModel` — parent-scoped sync

Adds one associated type (`SyncParent`) and one property (`parentRelationship`). Tells the engine which keypath is the parent relationship so it can scope queries and deletes to that parent.

**Used by:** a dedicated `sync(payload:as:parent:)` overload that constrains `Model: ParentScopedModel`. This is the only way to get the typed `parent: Model.SyncParent` parameter — if you removed this protocol, that overload would need to become `parent: Parent` (inferring from context) or take an explicit keypath argument.

### `ExportModel` — serialization

Adds one method: `exportObject(using:state:)`. Converts a model instance to `[String: Any]` for export.

**Used by:** `SwiftSync.export()`. The constraint ensures only exportable types can be exported.

### `SyncRelationshipSchemaIntrospectable` — macro metadata

Provides `syncRelationshipSchemaDescriptors`: a static list of relationship metadata (property name, related type name, cardinality) generated at compile time.

**Used by:** the engine's relationship resolution logic to know the schema without runtime reflection.

---

## The Real Cost

The protocols serve one purpose: **making the generic entry points type-safe**. The constraint `Model: SyncUpdatableModel` means the compiler verifies at the call site that `Note.self` (or whatever you pass) actually knows how to sync. Without the protocol, you'd either use `Any` (no type safety) or every sync call would be an untyped function taking closures.

The cost is the layering:
- Eight protocols instead of one or two
- More generic overloads to keep in sync with each other
- More expansion surface for the macro
- More things to explain

---

## Should You Remove It?

The comment you received is correct that the hierarchy is larger than strictly necessary. Here's the practical breakdown:

**Easy wins (low risk, real simplification):**

- **Delete `SyncQuerySortableModel`** — fold the sort sugar directly into `SyncModelable` with a default `nil` implementation. The `SyncQuery` sort overloads still work, you just lose one protocol declaration. Net change: `-1 protocol, ~0 behavior change`.

- **Delete `SyncRelationshipSchemaIntrospectable`** as a public protocol — make it internal/SPI. App code never references it; it's purely plumbing for the macro's relationship resolver.

**Medium complexity:**

- **Collapse `SyncUpdatableModel` + `SyncRelationshipUpdatableModel` into one** — since the engine already runtime-casts for relationships, the separation between "basic updatable" and "relationship updatable" doesn't enforce anything useful at the call site. One combined protocol would work.

**Harder (more architectural change):**

- **Replace `ParentScopedModel` with a static property** (e.g. `static var syncParentRelationship: AnyKeyPath?`) — you'd lose the typed `SyncParent` associated type, meaning the `sync(parent:)` overload becomes `sync<Parent: PersistentModel>(parent: Parent)` with the relationship resolved at runtime. This is the `inferred parent sync` path that already exists. The downside is that ambiguous relationships would be a runtime error instead of a compile-time one.

- **Delete `ExportModel`** as a separate protocol and fold it into the combined model protocol — you'd lose the ability to `sync` without `export`, but in practice all `@Syncable` models already conform to both, so this doesn't restrict real usage.

**The bottom line:**

If your only consumers of these protocols are `@Syncable` models, the hierarchy is doing almost no real work — the macro generates everything and users never see it. The protocols exist to make the engine's generic constraints precise. Collapsing to 3 protocols (one model protocol, one export protocol, one schema protocol) is viable without losing observable behavior, but requires touching the macro output, the engine entry points, and the query overloads simultaneously.

The smallest safe first move is to delete `SyncQuerySortableModel` (fold into `SyncModelable` with a default) and make `SyncRelationshipSchemaIntrospectable` internal. That removes two public protocol declarations with minimal risk.
