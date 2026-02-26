# SwiftSync Architecture

## Package Structure

5 library targets, 1 compiler plugin, 1 ObjC helper:

```
Core                    (no dependencies)
  ↑
  ├─ MacrosImplementation  (compiler plugin, + swift-syntax)
  │     ↑
  │     └─ Macros          (public macro declarations)
  │
  ├─ SwiftDataBridge       (sync engine)
  │
  └─ TestingKit            (test helpers)

SwiftSync                 (container + reactive queries)
  depends on: Core, SwiftDataBridge, Macros, ObjCExceptionCatcher

ObjCExceptionCatcher      (mixed Swift/ObjC, catches NSException from ModelContainer)
```

### What lives where

| Target | Key types |
|---|---|
| Core | `SyncPayload`, `SyncDateParser`, all protocols, `ExportKeyStyle`, `SyncError` |
| SwiftDataBridge | `SwiftSync.sync()`, `SwiftSync.export()`, `SyncLeaseRegistry` |
| MacrosImplementation | `SyncableMacro` + four no-op peer macros |
| Macros | `@Syncable`, `@PrimaryKey`, `@RemoteKey`, `@RemotePath`, `@NotExport` declarations |
| SwiftSync | `SyncContainer`, `SyncQuery`, `SyncModel` |
| ObjCExceptionCatcher | `SwiftSyncObjCExceptionCatcher` |

---

## Protocol Hierarchy

```
PersistentModel (SwiftData)
  └─ SyncModelable          syncIdentity, syncIdentityRemoteKeys, syncDefaultRefreshModelTypes,
    │                       syncSortDescriptor(for:), syncRelationshipSchemaDescriptors
    └─ SyncUpdatableModel       make(from:), apply(_:) → Bool,
          │                     applyRelationships(_:in:operations:) → Bool (default no-op)
          └─ ParentScopedModel  parentRelationship keypath

SyncModelable
  └─ ExportModel             exportObject(using:state:) → [String: Any]
```

**@Syncable makes a class conform to all of:**
`SyncUpdatableModel`, `ExportModel`

---

## The Sync Pipeline

```
Raw [Any] payload (array of dicts)
    │
    ▼ normalize()
[[String: Any]]
    │
    ▼ per entry: SyncPayload(values:, keyStyle:)
Wraps dict with key resolution + coercion
    │
    ▼ resolveIdentity()
SyncID (String/Int/UUID…)
    │
    ▼ identityKey() / scopedIdentityKey()
String key for index lookup
    │
    ├─ found in index → row.apply(payload)          update scalars
    └─ not found      → Model.make(from: payload)   create + insert
                               ↓
                     applyRelationships(payload, context, operations)
                               ↓
                     context.save()
                               ↓
                     post didSaveChangesNotification
```

### SyncPayload: key resolution + coercion

`candidateKeys(for: "assigneeId")` on `.snakeCase` input generates:
1. `"assignee_id"` (snake-cased version)
2. `"assigneeId"` (original)
3. Special cases for `"id"` / `"remoteID"`

Result cached per `SyncPayload` instance in `CandidateKeysCache`.

**Null semantics (strict):**
- Key absent → ignore, no mutation
- Key present as `NSNull` → clear / delete
- Key present as value → apply

**Coercion in `value(for:as:)`:**
`"42"` → `Int`, `1` → `Bool`, `"2025-01-01"` → `Date`, `"uuid-string"` → `UUID`, etc.

**`required(for:)` vs `strictValue(for:)`:**
- `required` uses coercion + Date fallback to epoch + null defaults; throws on unresolvable
- `strictValue` uses direct cast only, returns nil silently

### Identity policy

- `.global` — identity unique across all rows (default)
- `.scopedByParent` — identity unique within parent scope
  - Scoped key: `"TypeName|<PersistentIdentifier>|<identityValue>"`
  - Default for `ParentScopedModel`

### Duplicate handling

Before processing entries, old rows with the same identity key are deleted. This cleans up any duplicates that crept in from previous partial syncs.

---

## What @Syncable Generates

Given:
```swift
@Syncable
@Model
final class Task {
    @Attribute(.unique) var id: String
    @RemoteKey("state.id") var stateID: String
    var title: String
    var assignee: User?
    var tags: [Tag]
    @NotExport var internalFlag: Bool
    init(...) { ... }
}
```

The macro emits an `extension Task: SyncUpdatableModel, ExportModel, ...` containing:

**`typealias SyncID = String`**
**`static var syncIdentity: KeyPath<Task, String> { \.id }`**

**`static func make(from payload: SyncPayload) throws -> Task`**
- `id`: `try payload.required(String.self, for: "id")`
- `stateID`: `try payload.required(String.self, for: "state.id")`
- `title`: `try payload.required(String.self, for: "title")`
- `assignee`: `nil` (relationship, skipped)
- `tags`: `[]` (to-many, skipped)
- `internalFlag`: `try payload.required(Bool.self, for: "internalFlag")`

**`func apply(_ payload: SyncPayload) throws -> Bool`**
- Skips `id` (primary key)
- Skips `assignee`, `tags` (relationships)
- For each scalar: if `payload.contains(key)`, read + compare, set + mark changed

**`func applyRelationships(_:in:operations:) -> Bool`**
- For `assignee`: if `payload.contains("assignee_id")` → `syncApplyToOneForeignKey`
- For `tags`: if `payload.contains("tags_ids") || payload.contains("tag_ids")` → `syncApplyToManyForeignKeys`
  - else if `payload.contains("tags")` → `syncApplyToManyNestedObjects`

**`func exportObject(using:state:) -> [String: Any]`**
- `internalFlag` skipped (`@NotExport`)
- `stateID` exported under key `"state.id"` (nested dict)
- `assignee` exported as object or NSNull
- `tags` exported as array of objects

**`static func syncSortDescriptor(for keyPath:) -> SortDescriptor<Task>?`**
- Returns `SortDescriptor(\Task.title)` if `keyPath == \Task.title`, etc.
- Only for Comparable scalar types (String, Int, Date, UUID, …)

**`static var syncRelationshipSchemaDescriptors`**
- Metadata for schema validation: each relationship's name, related type, isToMany, hasExplicitInverse

### Macro attributes

| Attribute | Effect on make/apply | Effect on export |
|---|---|---|
| `@PrimaryKey` | Sets `syncIdentity`; skipped in `apply` | Exported normally |
| `@PrimaryKey(remote: "ext_id")` | Sets `syncIdentityRemoteKeys: ["ext_id"]` | Exported under `"ext_id"` |
| `@RemoteKey("key")` | Read from `"key"` in payload | Exported under `"key"` |
| `@RemotePath("a.b")` | Read from nested `payload["a"]["b"]` | Exported to nested dict |
| `@NotExport` | Normal sync | Excluded from export |

---

## Relationship Resolution (Core.swift globals)

Four public overloaded functions, each in two variants (concrete `PersistentModel` = no-op stub, `SyncModelable`/`SyncUpdatableModel` = real logic):

```
syncApplyToOneForeignKey    — Model? property, resolved by ID lookup
syncApplyToManyForeignKeys  — [Model] property, resolved by ID array
syncApplyToOneNestedObject  — Model? property, resolved by nested dict
syncApplyToManyNestedObjects — [Model] property, resolved by nested dicts
```

The stubs (`Related: PersistentModel` constraint) exist so the macro-generated code compiles cleanly even when the related type doesn't conform to `SyncModelable` — the stub silently returns `false`.

**`SyncRelationshipOperations` bitmask**
- `.insert` — create new related rows
- `.update` — modify existing related rows
- `.delete` — remove relationships / delete children
- `.all` — default

**`mergeUnorderedRelationships`**: merges current + desired arrays respecting allow/delete flags, used for all to-many operations.

---

## The Concurrency Lease

**Problem:** Multiple concurrent `sync()` calls on the same container would race on shared SwiftData state.

**Solution in `SyncLeaseRegistry` (actor):**

```
acquireSyncLease(for context)
  scopeID = ObjectIdentifier(context.container)
  if scopeID not active → mark active, return lease immediately
  else → enqueue CheckedContinuation, suspend

releaseSyncLease(lease)
  if waiters exist → resume first waiter (FIFO)
  else → mark scope inactive
```

Lease always released in `defer`-equivalent pattern:
```swift
let lease = await acquireSyncLease(for: context)
do {
    // ... sync work ...
    await releaseSyncLease(lease)
} catch {
    await releaseSyncLease(lease)   // always release
    if isCancellation(error) {
        context.rollback()
        throw SyncError.cancelled
    }
    throw error
}
```

---

## SyncContainer

Thin orchestration layer over `SwiftSync.*` functions:

- Stores `ModelContainer`, `mainContext`, `inputKeyStyle`
- Creates a fresh `ModelContext` per `sync()` call (background context)
- Observes `ModelContext.didSave` on all contexts → re-posts as `SyncContainer.didSaveChangesNotification` with:
  - `changedIdentifiers`: union of inserted + updated + deleted IDs
  - `changedModelTypeNames`: type names derived from those IDs

**Initialization pipeline:**
```
validateSchema (if .failFast)
  ↓
Schema(modelTypes)
  ↓
_executeCatchingObjectiveCException {
    ModelContainer(for:schema, migrationPlan:, configurations:)
}
  ↓ (if fails + recovery == .resetAndRetry)
_resetPersistentStoreFiles(for:)   ← deletes .sqlite + sidecar files
  ↓
retry ModelContainer(...)
```

**`_resetPersistentStoreFiles`:** enumerates the directory of each configuration URL, deletes files whose names start with the database filename. Catches SQLite WAL/SHM sidecars.

---

## Reactive Query System

```
SyncContainer.didSaveChangesNotification
        │
        ▼
SyncQueryObserver.shouldReload(for notification)
  1. changedModelTypeNames empty? → reload (no type info, be safe)
  2. changedModelTypeNames ∩ observedModelTypeNames non-empty? → reload
  3. changedIDs ∩ loadedRowIDs non-empty? → reload (a loaded row changed)
  4. otherwise → skip
        │
        ▼  (if reload)
FetchDescriptor<Model>(predicate:, sortBy:)
  + optional postFetchFilter (for relatedTo queries)
        │
        ▼
withAnimation(animation) { rows = resolved }
```

**`observedModelTypeNames` built at init:**
- Always includes `String(reflecting: Model.self)`
- Plus `syncDefaultRefreshModelTypeNames` (declared by the model)
- Plus `syncRefreshModelTypeNames(for: refreshOn)` (from `refreshOn:` parameter)

**`postFetchFilter` for relatedTo queries:**
- Inferred: tries `inferToOneRelationship` + `inferToManyRelationship`; picks whichever succeeds alone
- Explicit `through: \Task.assignee` → `explicitToOneRelatedIDFilter`
- Explicit `through: \Task.reviewers` → `explicitToManyRelatedIDFilter`

---

## Export System

```swift
SwiftSync.export(as: Task.self, in: context, using: options)
```

1. Fetch all rows, sort by identity key string
2. For each row: `row.exportObject(using: options, state: &ExportState())`
3. Each call to `exportObject`:
   - `state.enter(self)` — guard against cycles
   - For each non-`@NotExport` property:
     - Scalar: `exportEncodeValue(value, options)` → encode
     - Optional scalar: encode or NSNull if nil + `includeNulls`
     - Relationship: recurse via `exportObject` on children
   - Key from `@RemoteKey`/`@RemotePath` or `options.keyStyle.transform(propertyName)`
   - `exportSetValue(value, for: keyPath, into: &result)` — supports nested dot-path keys
   - `state.leave(self)`

**`ExportRelationshipMode`:**
- `.array` → `"tags": [{...}, {...}]`
- `.nested` → `"tags_attributes": {"0": {...}, "1": {...}}` (Rails-style)
- `.none` → key omitted entirely

---

## Schema Validation

Only runs when `schemaValidation: .failFast`. Detects many-to-many pairs where neither side has `@Relationship(inverse: …)`, which would silently create two separate join tables in SwiftData.

```
for each isToMany relationship R:
    find reciprocals = all isToMany on R.relatedType pointing back to R.ownerType
    if reciprocals exist:
        if neither R nor any reciprocal has hasExplicitInverseAnchor:
            throw SchemaValidationError
```

`hasExplicitInverseAnchor` is detected by the macro scanning for `@Relationship` attributes with an `inverse:` argument.

---

## ObjC Exception Bridge

`ModelContainer(for:)` can raise NSException (e.g., store migration failures) which Swift cannot catch with `do/catch`. The bridge:

1. ObjC: `@try { block() } @catch (NSException *e) { wrap in NSError }`
2. Swift: calls bridge, checks `swiftResult` (set inside block), extracts name/reason from NSError userInfo

Error type: `ObjectiveCInitializationExceptionError` with `name` + `reason` from exception.

---

## Things Worth Reducing

Areas with the most surface area relative to usage:

1. **Four relationship application globals** — each exists in two overloads (stub + real). The stubs return `false` unconditionally. If all related types were required to be `SyncModelable`, the stubs could disappear (8 functions → 4).

2. **`ExportRelationshipMode.nested`** — the `.nested` / `_attributes` output mode (Rails-style). If unused in your app, the branch can be deleted from the macro's generated export code.

3. **`SyncInputKeyStyle.camelCase`** — if all your payloads are snake_case, the camelCase branch in `candidateKeys` is dead weight.

4. **`SyncMissingRowPolicy.keep`** — if you always delete missing rows, this branch is unused.

5. **Date parser breadth** — handles 15+ ISO8601 variants + Unix timestamps. If your server only emits one format, most branches are never hit.
