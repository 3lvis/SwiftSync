# Property Mapping Migration Notes

Use this when moving existing SwiftSync models to the current convention-first mapping behavior.

## 1) Remove redundant `@RemoteKey` where convention now matches

Before:

```swift
@RemoteKey("project_id")
var projectID: String
```

After:

```swift
var projectID: String
```

Why: acronym-aware snake conversion now maps `projectID <-> project_id`.

## 2) Keep `@RemoteKey` when local name intentionally differs

Before and after (keep this):

```swift
@RemoteKey("description")
var descriptionText: String
```

Why: local name (`descriptionText`) intentionally differs from payload key (`description`).

## 3) Configure inbound key style once at container level

Default snake_case:

```swift
let syncContainer = try SyncContainer(
  for: User.self,
  inputKeyStyle: .snakeCase
)
```

CamelCase backend:

```swift
let syncContainer = try SyncContainer(
  for: User.self,
  inputKeyStyle: .camelCase
)
```

## 4) Use `@RemotePath` for nested payload keys (import + export)

```swift
@RemotePath("profile.contact.email")
var email: String?
```

Behavior:
- missing deep key => no-op
- deep key with `null` => clear
- export writes the same nested key path

## 5) Blocked property names in `@Syncable` models

Avoid:
- `description`
- `hashValue`

Use:
- `descriptionText`
- `hashValueRaw`

If backend keys still use blocked names, map with `@RemoteKey`.

## 6) Relationship FK strictness is unchanged

Relationship IDs remain strict:
- `company_id: 10` links to `Int` identity
- `company_id: "10"` does not link to `Int` identity

Scalar attribute coercions are broader, but relationship FK matching still uses strict reads.

## 7) Relationship naming to avoid explicit key mapping

If backend sends `author_user_id`, prefer relationship/property names that map by convention:

```swift
var authorUserID: String
var authorUser: User?
```

This avoids explicit `@RemoteKey("author_user_id")` on relationship fields.
