# Reactive Reads

SwiftSync provides three reactive local read APIs:

- `@SyncQuery` (SwiftUI list reads)
- `@SyncModel` (SwiftUI detail reads by identity)
- `SyncQueryPublisher` (UIKit/plain Swift class-based reads)

These APIs read from local `SwiftData` (`syncContainer.mainContext`). They do not call the network.

## Query shapes

`@SyncQuery` and `SyncQueryPublisher` support the same query shapes:

1. Full model fetch
2. Predicate-based fetch
3. Relationship-scoped fetch (`relationship:` + `relationshipID:`)

To-one relationship example:

```swift
@SyncQuery(
  Task.self,
  relationship: \Task.project,
  relationshipID: projectID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Task.id)]
)
var tasks: [Task]
```

To-many relationship example:

```swift
@SyncQuery(
  Project.self,
  relationship: \Project.tasks,
  relationshipID: taskID,
  in: syncContainer,
  sortBy: [SortDescriptor(\Project.id)]
)
var projects: [Project]
```

## Refresh behavior

- `SyncContainer` observes background save notifications.
- After sync writes, it posts an internal `didSaveChangesNotification`.
- Reactive wrappers observe that notification and reload from `mainContext`.

In practice, this gives the "sync local data, UI re-renders from local store" flow.

## `refreshOn` (SwiftUI only)

When `Model` conforms to `SyncModelable`, `@SyncQuery` has overloads with `refreshOn:`.

- `refreshOn:` adds related model types to the query's observed type set.
- Use it when a screen renders related-model fields and should refresh when those related models change.

## App usage guidelines

- Keep network calls and sync orchestration in a domain/service layer.
- Keep views focused on local reads and user interaction.
- Pass IDs/scalars between views instead of passing `SwiftData` model instances around.
