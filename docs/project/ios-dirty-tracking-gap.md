# iOS Dirty-Tracking Gap in To-Many Relationships

## Status

Mitigated in SwiftSync.

## Problem

On iOS, changing only a to-many relationship can fail to mark the owning row as updated for save-observer purposes.

That can leave reactive reads stale if no scalar field changes in the same write.

## Current mitigation

`syncApplyToManyForeignKeys` calls `owner.syncMarkChanged()` whenever membership changes.

- `@Syncable` generates `syncMarkChanged()` as a scalar self-write (`self.id = self.id`).
- Manual `SyncUpdatableModel` conformances get a default no-op and should override `syncMarkChanged()` when needed.

## Verification

Covered by `SyncMarkChangedCallSiteTests` in `SwiftSync/Tests/SwiftSyncTests/SyncRelationshipIntegrityTests.swift`.
