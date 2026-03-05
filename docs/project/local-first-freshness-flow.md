# Demo Local-First Freshness Flow

This demo now teaches a local-first sync pattern with explicit freshness policy.

## Normal flow

- Screens render from local SwiftData immediately.
- Engine evaluates freshness per dataset key (`DataKey`).
- If local data is fresh, the engine runs a background network refresh (`local-first refresh`).
- If local data is empty or stale, the engine runs a blocking network fetch (`network-first load`).
- Pull-to-refresh and Retry always force network-only behavior.

## Engine boundaries

- `load*` methods in `DemoSyncEngine` are orchestration entry points (local-first + freshness + status).
- `sync*` methods remain explicit network primitives.
- Views should call `load*` for screen lifecycle and use `sync*` only for explicit mutation-followup primitives.

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
- **UI remains stale**: verify scope status is not `failed`; use Retry (network-only).
- **Unexpected network fetches**: verify TTL for that namespace and last-success timestamp updates.
- **Form metadata looks stale**: Retry in form state section forces network-only refresh.
