# Upload Endpoint Contract

The wire contract for SwiftSync's **push** (local → server). A general-purpose backend
(Django/Rails/Laravel/Spring) adds this as one thin "offline layer" endpoint *beside* its normal
per-resource routes — backed by the framework's bulk-upsert primitive (`upsert_all` / `upsert()` /
`saveAll`). It does not replace the existing CRUD API; it is the batched sync seam.

This is a *dictated* contract: to use offline push, the backend implements this endpoint. That is the
deliberate trade (see `docs/planning/production-sync-design.md`) — one well-defined path beats
adapting to every backend's ad-hoc bulk convention.

## Endpoint

```
POST /sync/upload
```

A single batched request carrying all pending local changes. Returns a per-operation result list.

## Identity: two ids

Every syncable row has two ids:

- **`localId`** — client-generated, stable forever, never changes. SwiftSync mints it (a UUID) the
  moment the row is created offline. It is also the **idempotency key** (see below).
- **`remoteId`** — the server's own canonical id, minted by the server on insert. **Opaque to
  SwiftSync** — it may be a UUID, an integer, a slug, anything; SwiftSync carries it as a string at
  the boundary (an integer-PK backend just stringifies). `nil` on the client until an insert is
  acknowledged.

The server does **not** accept the client's id as canonical — it mints its own. This is what lets
SwiftSync work with conventional backends (including legacy integer-PK ones), not just greenfield
UUID schemas. The cost SwiftSync owns is the local id-rewrite when `remoteId` arrives.

## Request

```json
{
  "operations": [
    { "operation": "insert", "type": "tasks", "localId": "0c1f…",
      "updatedAt": "2026-06-16T20:00:00Z", "data": { "title": "Draft", "state": {"id": "todo"} } },

    { "operation": "update", "type": "tasks", "remoteId": "8842",
      "updatedAt": "2026-06-16T20:01:00Z", "data": { "title": "Renamed", "state": {"id": "todo"} } },

    { "operation": "delete", "type": "tasks", "remoteId": "7710",
      "updatedAt": "2026-06-16T20:02:00Z" }
  ]
}
```

Per operation:

| field | insert | update | delete |
|---|---|---|---|
| `operation` | `"insert"` | `"update"` | `"delete"` |
| `type` | resource name (consumer-chosen) | same | same |
| `localId` | **required** | — | — |
| `remoteId` | — | **required** | **required** |
| `updatedAt` | required (ISO 8601) | required | required |
| `data` | full resource | **full resource** (not a diff) | — |

- **`data` is the full resource, not a delta.** SwiftSync has no field-level dirty tracking
  (`export(row)` emits the whole object), so an update sends every field. The server applies them
  under SwiftSync's payload semantics: a present field is set, an explicit `null` clears it.
- Operations are applied **in array order**.

## Semantics

### Idempotency — the server stores `localId`

Insert hazard: the client posts an insert, the server creates the row and mints `remoteId`, but the
**response is lost** (network drop). The client still has no `remoteId`, so it retries the same
insert. The server **must not** create a second row.

The server persists `localId` (a column, unique per `type` + tenant) alongside `remoteId`. On insert
it keys on `(type, localId)`: if a row with that `localId` already exists, it returns the **existing**
`remoteId` (`status: "applied"`) instead of creating again. Inserts are therefore safe to retry
indefinitely.

### Conflict — server-authoritative last-writer-wins

For update/delete, the server compares the incoming `updatedAt` with the stored `updatedAt`:

- incoming **newer** ⇒ apply.
- incoming **older or equal** ⇒ the server keeps its version and returns it (`status: "stale"`, with
  the current server row in `server`). SwiftSync adopts the server state locally.

### Delete is a soft-delete tombstone

A delete marks the row deleted (retained for a TTL) so other clients pull the deletion via the pull
endpoint. It is not an immediate hard-delete.

### Safety: destruction is always explicit

- **`operation` is required.** Missing or unknown ⇒ the operation is **rejected** — the server never
  guesses and never falls back to delete (fail-closed).
- **Only `"delete"` deletes.** A forgotten `data` on an insert/update is a rejected insert or a no-op
  update — never a delete.

This mirrors the payload semantics symmetrically: an *absent field* never clears a value (you must
send explicit `null`); an *absent operation* never destroys a row (you must send explicit
`"delete"`). The destructive path is always opt-in, never the default. (This is also why the
op-tagged list is safer than a set-diff: a row simply not appearing means "no change," never
"delete.")

## Response

A per-operation result list (partial success — one bad row never blocks the batch):

```json
{
  "results": [
    { "operation": "insert", "localId": "0c1f…", "remoteId": "8843", "status": "applied" },
    { "operation": "update", "remoteId": "8842", "status": "stale",
      "server": { "remoteId": "8842", "title": "Edited elsewhere",
                  "updatedAt": "2026-06-16T20:05:00Z" } },
    { "operation": "delete", "remoteId": "7710", "status": "applied" },
    { "operation": "update", "remoteId": "9001", "status": "rejected",
      "code": "validation", "message": "title must not be empty" }
  ],
  "cursor": "2026-06-16T20:02:00Z"
}
```

| `status` | meaning | SwiftSync reaction |
|---|---|---|
| `applied` | written (LWW won, or idempotent re-ack) | confirm; stamp `remoteId` onto the inserted row |
| `stale` | the client write lost LWW; `server` carries current truth | adopt the server state locally |
| `rejected` | permanent/validation failure | surface `message` (+ `code`) in the failures inbox (discard / edit / retry) |

- Insert results echo `localId` so SwiftSync can map the assigned `remoteId` back onto the right row.
- `rejected` carries a human-readable `message` and an optional machine `code`.
- `cursor` is an **opaque** string (a timestamp or token — the server decides). The client feeds it to
  the pull side; SwiftSync treats it as opaque.

## Pull pairing (out of scope here, for orientation)

The `cursor` from a successful upload is fed to the inbound pull, conceptually
`GET /sync/pull?since=<cursor>`, which returns changes since the cursor (including tombstones). That
inbound direction is SwiftSync's existing `sync` (server → SwiftData). Push and pull share the cursor.

## Layering on a general-purpose backend

It is one custom controller action:

1. Parse `operations`, group by `type`.
2. Per operation: resolve the row (insert → by `(type, localId)`; update/delete → by `remoteId`),
   apply LWW, upsert / tombstone via the ORM's bulk primitive.
3. Return the per-operation `results` + a `cursor`.

Existing per-resource endpoints are untouched — this sits beside them. A real backend scopes every
operation to the authenticated principal and rejects cross-tenant references (`status: "rejected"`);
large pushes are chunked client-side rather than capped by a hard server limit.
