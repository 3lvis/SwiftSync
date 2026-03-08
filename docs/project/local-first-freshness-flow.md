# Demo Local-First Freshness Flow

This demo now teaches a local-first sync pattern without TTL-based skip logic.

## Normal flow

- Screens render from local SwiftData immediately.
- Engine always refreshes from network when a screen triggers sync.
- There is no pull-to-refresh in demo screens.
- Retry uses the same `sync*` method.

## Engine boundaries

- One public `sync*` call exists per screen flow in `DemoSyncEngine`.
- Screen entrypoints call only `syncProjects`, `syncProjectTasks`, `syncTaskDetail`, or `syncTaskFormMetadata`.
- Views do not pass freshness hints or reasons.

## Error/state boundaries

- Engine publishes `isSyncing`.
- Sync methods throw; call sites decide retry and user messaging.

## Earthquake Mode boundaries

- Earthquake Mode is DEBUG-only and opt-in.
- It is triggered by shake + confirmation on detail screens.
- It is never part of normal sync orchestration.
- It exists only to stress overlap between refresh and mutation paths.

## What this teaches SwiftSync adopters

- Keep business sync policy in an engine, not in views.
- Prefer one simple `sync*` API per screen flow.
- Keep local-first UX by binding UI to local models and always refreshing network after entry.

## Troubleshooting

- **UI shows old data briefly**: expected in local-first mode; wait for network sync completion.
- **UI remains stale**: use the screen-level retry action and verify the screen-level error copy.
- **Form metadata looks stale**: retry metadata load in the form.
