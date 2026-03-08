# Demo Local-First Freshness Flow

This demo now teaches a local-first sync pattern without TTL-based skip logic.

## Normal flow

- Screens render from local SwiftData immediately.
- Engine always refreshes from network when a screen triggers sync.
- There is no pull-to-refresh in demo screens.

## Engine boundaries

- One public `sync*` call exists per screen flow in `DemoSyncEngine`.
- Screen entrypoints call only `syncProjects`, `syncProjectTasks`, `syncTaskDetail`, or `syncTaskFormMetadata`.
- Views do not pass freshness hints or reasons.

## Error/state boundaries

- Engine publishes `isSyncing`.
- Sync methods throw; call sites decide user messaging.

## What this teaches SwiftSync adopters

- Keep business sync policy in an engine, not in views.
- Prefer one simple `sync*` API per screen flow.
- Keep local-first UX by binding UI to local models and always refreshing network after entry.

## Troubleshooting

- **UI shows old data briefly**: expected in local-first mode; wait for network sync completion.
- **UI remains stale**: leave and re-enter the screen to trigger a fresh sync.
