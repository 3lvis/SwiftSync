# Demo Engine Local-First Refresh Flow

## Goal

One engine sync call per screen flow.

The screen should:

- bind to reactive local models (`@SyncQuery` / `@SyncModel`),
- call one engine `sync*` method,
- render updates as data changes,
- not care whether values came from local cache or backend.

## Constraints

- No bootstrap prefetch path.
- No startup metadata sync.
- No TTL/staleness skip logic.

## Required behavior

For each screen entry point, engine executes:

- local data visible immediately when available,
- always refresh from network,
- reactive store updates when backend returns changed rows.

There is no pull-to-refresh path in demo screens.

## Open items

- [ ] Manual pass: confirm each screen calls only one public `sync*` method and no direct data helper methods.

## Non-goals

- Push/WebSocket/SSE integration.
- Offline mutation queue redesign.
- Broad SwiftSync core API redesign.
