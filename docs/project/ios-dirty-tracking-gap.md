# iOS Dirty-Tracking Gap in To-Many Relationships

## Status

Mitigated in SwiftSync.

The underlying SwiftData/Core Data behavior still matters on iOS: a write that only changes
to-many membership can fail to mark the owning row dirty. SwiftSync now compensates for that
case when relationship sync actually changes membership.

This matters to iOS stores because `ModelContext.didSave` may otherwise omit the owner's
`PersistentIdentifier`, which prevents `SyncContainer.modelContextDidSave` from propagating the
change immediately to `@SyncModel` / `@SyncQuery` observers.

## Failure mode

The problematic shape is:

- the owning model changes only a to-many relationship
- no scalar property changes on the same save
- the UI depends on `ModelContext.didSave` for reactive refresh

Example:

```swift
task.reviewers = [u1, u2]
```

Without an accompanying scalar write, iOS can skip dirty-marking the owning row even though the
relationship membership changed.

## SwiftSync behavior

`syncApplyToManyForeignKeys` and `syncApplyToManyNestedObjects` now call
`owner.syncMarkChanged()` only when to-many membership actually changes.

For `@Syncable` models, the macro-generated implementation performs:

```swift
self.id = self.id
```

That intentional no-op scalar write is enough to force iOS/Core Data to treat the owner as
updated for notification purposes.

For hand-written `SyncUpdatableModel` conformances, the protocol default remains a no-op:

```swift
func syncMarkChanged() {}
```

If a hand-written model owns synced to-many relationships, override `syncMarkChanged()`
explicitly. Otherwise the dirty-tracking gap can still surface for that model on iOS when
foreign-key or nested-object relationship sync changes membership.

## Notification detail

When inspecting `ModelContext.didSave`, use the plain `userInfo` keys `"updated"` and
`"inserted"`.

Do not use `ModelContext.NotificationKey.updatedIdentifiers` here. That constant resolves to
`"updatedIdentifiers"`, which does not match the values currently placed in the notification
dictionary for this flow.

## Current coverage

- Library contract: `SyncMarkChangedCallSiteTests` in
  `SwiftSync/Tests/SwiftSyncTests/SyncRelationshipIntegrityTests.swift`
  verifies both `syncApplyToManyForeignKeys` and `syncApplyToManyNestedObjects` call
  `syncMarkChanged()` after real membership changes, do not call it when membership is unchanged,
  and call it after explicit clears.
- End-to-end regression: `DirtyTrackingGapTests` in
  `DemoCore/Tests/DemoCoreTests/DirtyTrackingGapTests.swift`
  verifies the owning `Task` identifier appears in `ModelContext.didSave` for both persistent and
  in-memory stores after a to-many-only write.

## Practical guidance

- Prefer `@Syncable` for models that own synced to-many relationships.
- If you cannot use `@Syncable`, implement `syncMarkChanged()` yourself.
- Treat this as an iOS-specific runtime workaround, not as evidence that SwiftData itself is fully
  fixed.
