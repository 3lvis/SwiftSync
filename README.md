# SwiftSync

SwiftSync is a focused SwiftData sync and export library.

- Inbound sync: JSON payload -> local SwiftData models
- Outbound export: local SwiftData models -> API-ready JSON payloads

It is designed for deterministic behavior, low configuration, and clear conventions.

## Installation

Add the package to your project and import:

- `SwiftSync`

`SwiftSync` is the umbrella module that re-exports the public API, including macros.

## Public API

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

## Quick Start

```swift
import SwiftData
import SwiftSync

@Syncable
@Model
final class User {
  @Attribute(.unique) var id: Int
  var name: String
  var updatedAt: Date?

  init(id: Int, name: String, updatedAt: Date? = nil) {
    self.id = id
    self.name = name
    self.updatedAt = updatedAt
  }
}

let payload: [Any] = [
  ["id": 1, "name": "Elvis", "updated_at": "2014-02-17T00:00:00+00:00"],
  ["id": 2, "name": "Maya"]
]

try await SwiftSync.sync(payload: payload, as: User.self, in: context)
let rows = try SwiftSync.export(as: User.self, in: context)
```

## Modeling

### `@Syncable` default behavior

`@Syncable` generates sync/export boilerplate for model properties.

Identity selection order:
1. A property marked with `@PrimaryKey` (or `@PrimaryKey(remote: ...)`)
2. `id`
3. `remoteID`

### Custom identity key

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

### Custom remote identity name

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

### Export-only field mapping controls

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

## Sync Scenarios

### 1. Full payload source of truth (insert/update/delete)

If local has ids `{0,1,2,3,4}` and payload has `{0,1,6}`:

- `0,1` update in place
- `6` inserts
- `2,3,4` delete
- final local ids are exactly `{0,1,6}`

### 2. Invalid identity rows are skipped

Rows with missing or `null` identity are ignored for matching/diffing.
Valid rows still sync normally.

### 3. Local duplicate identity dedupe

If local database has accidental duplicate rows with the same primary key, SwiftSync compacts them during sync and continues safely.

### 4. Field-by-field no-op updates

For existing rows, `apply(_:)` returns `true` only when a field value actually changes.
No write means no save for that row change path.

### 5. Null handling for scalars

- Optional scalar + `null` -> `nil`
- Non-optional primitive + `null` -> type default (`""`, `0`, `false`, epoch date, zero UUID)
- No throw for this case

### 6. Key mapping in payload lookup

`SyncPayload` supports common API key shape differences:

- snake_case -> camelCase (e.g. `updated_at` -> `updatedAt`)
- identity aliases (`id`, `remote_id`, `remoteID`)

### 7. Relationship sync in same pass

If model also conforms to `SyncRelationshipUpdatableModel`, relationships are applied during the sync run.

Supported patterns in `applyRelationships(...)`:

- to-one nested object (`"company": {...}`)
- to-one by foreign key (`"company_id": 10`)
- to-many nested objects (`"notes": [{...}]`)
- to-many by ids (`"notes_ids": [1,2]`)

Expected semantics:

- payload membership is source of truth
- repeated identical payload is idempotent
- missing referenced rows do not crash

### 8. Parent-scoped child sync

Use the parent overload when payload is child-only but scoped to one parent.

```swift
try await SwiftSync.sync(
  payload: notesPayload,
  as: Note.self,
  in: context,
  parent: user
)
```

Behavior:

- created/updated children are linked to that parent
- delete/diff scope is restricted to that parent's children
- children of other parents are unaffected

## Export Scenarios

### Default export

```swift
let rows = try SwiftSync.export(as: User.self, in: context)
```

Defaults:

- key style: snake_case
- relationship mode: `.array`
- date format: ISO-style UTC formatter
- nulls: included (`NSNull`)

### CamelCase export

```swift
var options = ExportOptions.camelCase
let rows = try SwiftSync.export(as: User.self, in: context, using: options)
```

### Exclude relationships

```swift
let rows = try SwiftSync.export(as: User.self, in: context, using: .excludedRelationships)
```

### Nested relationship mode (`*_attributes`)

```swift
var options = ExportOptions()
options.relationshipMode = .nested
let rows = try SwiftSync.export(as: User.self, in: context, using: options)
```

Shape examples:

- `.array`
```json
{
  "id": 1,
  "company": { "id": 7, "name": "Acme" },
  "notes": [{ "id": 10 }, { "id": 11 }]
}
```

- `.nested`
```json
{
  "id": 1,
  "company_attributes": { "id": 7, "name": "Acme" },
  "notes_attributes": {
    "0": { "id": 10 },
    "1": { "id": 11 }
  }
}
```

- `.none`
```json
{
  "id": 1,
  "name": "User"
}
```

### Custom date formatter

```swift
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(secondsFromGMT: 0)
formatter.dateFormat = "yyyy/MM/dd"

var options = ExportOptions()
options.dateFormatter = formatter

let rows = try SwiftSync.export(as: User.self, in: context, using: options)
```

### Parent-scoped export

```swift
let childRows = try SwiftSync.export(
  as: Note.self,
  in: context,
  parent: user
)
```

Only rows linked to that parent are exported.

### Recursion guard

Cyclic object graphs are safe; export uses a traversal guard to avoid infinite loops.

## Date Parsing

SwiftSync uses a custom parser for inbound date hot paths (`SyncDateParser`), not formatter-heavy parsing.

`SyncDateParser` supports:

- ISO-like strings with `Z`, `+00:00`, `+0000`, or no timezone (assumes UTC)
- date-only `YYYY-MM-DD` (normalized to UTC midnight)
- `YYYY-MM-DD HH:mm:ss` style (space replaced with `T`)
- fractional seconds: deciseconds, centiseconds, milliseconds, microseconds
- Unix timestamp strings/numbers (seconds and microseconds-like values)

Invalid date input behavior:

- parser returns `nil`
- sync does not crash
- optional date fields become `nil`
- required date fields fall back to epoch

our policy is honestly we do our best without affecting performance.

## Guarantees and Constraints

- Deterministic identity diffing
- Best-effort coercion for common payload types
- Skip invalid top-level identity rows instead of throwing
- Relationship updates are model-defined via `applyRelationships`
- No networking layer and no queue/reconciliation layer

## Error Behavior

Sync throws typed `SyncError` for structurally invalid operations (for example, non-dictionary payload rows).

For data quality issues in row content, behavior is intentionally lenient where possible:

- invalid identity rows: skipped
- invalid nullable values: mapped to `nil`/defaults when supported
- invalid dates: best-effort fallback behavior above

## Testing

Run all tests:

```bash
swift test
```

The suite covers:

- core date parser compatibility behavior
- identity diffing insert/update/delete
- invalid identity skip and dedupe
- relationship mapping (to-one, to-many, many-to-many)
- parent-scoped sync
- export modes/options/macro mapping controls
