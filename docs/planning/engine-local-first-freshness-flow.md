# Engine Local-First Freshness Flow (Current Plan)

## Goal

One engine call per screen flow.

The screen should:

- bind to reactive local models (`@SyncQuery` / `@SyncModel`),
- call one engine method,
- render updates as data changes,
- not care whether values came from local cache or backend.

## Constraints

- No backwards-compatibility layer for old orchestration APIs.
- No caller-provided "reason" for load strategy.
- Engine chooses load strategy internally.

## Required behavior

For each screen entry point, engine decides and executes:

- local data visible immediately when available,
- network-first when local is empty/stale,
- local-first refresh when local is fresh,
- reactive store updates when backend returns changed rows.

There is no pull-to-refresh path in demo screens.

## Open item

- Manual pass: confirm each screen only calls one engine load method.

## Non-goals

- Push/WebSocket/SSE integration.
- Offline mutation queue redesign.
- Broad SwiftSync core API redesign.
