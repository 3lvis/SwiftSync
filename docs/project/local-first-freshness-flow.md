# Demo Local-First Freshness Flow

This demo now teaches a local-first sync pattern with explicit freshness policy.

## Normal flow

- Screens render from local SwiftData immediately.
- Engine evaluates freshness per dataset key (`DataKey`).
- If local data is fresh, the engine runs a background network refresh (`local-first refresh`).
- If local data is empty or stale, the engine runs a blocking network fetch (`network-first load`).
- There is no pull-to-refresh in demo screens.
- Retry uses the same screen load call and re-evaluates freshness policy.

## Engine boundaries

- One public `load*Screen` call exists per screen flow in `DemoSyncEngine`.
- All screen interactions use the same `load*Screen` method (initial load + retry).
- `sync*` methods remain explicit network primitives.
- Views do not pass load hints/reasons; engine chooses the path internally.

## Scope status stream

Each scope publishes status by `DataKey`:

- `phase`: `idle | loading | refreshing | failed`
- `path`: `localFirstRefresh | networkFirst | networkOnly`
- `errorMessage` for actionable failures

The detail screens show this stream and expose Retry when failed.

## Earthquake Mode boundaries

- Earthquake Mode is DEBUG-only and opt-in.
- It is triggered by shake + confirmation on detail screens.
- It is never part of normal sync orchestration.
- It exists only to stress overlap between refresh and mutation paths.

## What this teaches SwiftSync adopters

- Keep business sync policy in an engine, not in views.
- Treat freshness as a policy decision over three facts: local presence, last successful sync, and TTL.
- Separate orchestration APIs (`load*`) from low-level network APIs (`sync*`).
- Publish scope-level status so UI can explain what is happening.

## Troubleshooting

- **UI shows old data briefly**: expected in local-first mode; check status path (`localFirstRefresh`) and wait for refresh completion.
- **UI remains stale**: verify scope status is not `failed`; use Retry.
- **Unexpected network fetches**: verify TTL for that namespace and last-success timestamp updates.
- **Form metadata looks stale**: retry metadata load in the form.
