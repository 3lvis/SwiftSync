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

## Identity: one client-owned id

Every syncable row has a single id, **client-generated and stable forever**. SwiftSync mints it (a
UUID) the moment the row is created offline, and it is the row's identity on both sides: the key the
server upserts on, the key inbound sync matches on, and the idempotency key.

This is the price of admission for offline push (see the iOS conventions' "be opinionated"): the
backend must accept client-supplied ids for synced resources rather than minting its own. In exchange
there is **no second id and no client-side id rewrite** — the Core Data id-mutation hazard never
arises, and `upsert`/`delete` address rows by the same id the client already holds.

(The alternative — the server minting a distinct `remoteId` so SwiftSync can reach legacy integer-PK
backends — is the two-id variant described in `production-sync-design.md`. The demo deliberately takes
the simpler single-id path; SwiftSync's push core supports both because `syncRemoteID` is just "the id
the server acknowledged," which here equals the client id.)

## Request

```json
{
  "operations": [
    { "operation": "upsert", "type": "tasks", "id": "0c1f…",
      "updatedAt": "2026-06-16T20:00:00Z", "data": { "id": "0c1f…", "title": "Draft", "state": {"id": "todo"} } },

    { "operation": "delete", "type": "tasks", "id": "7710",
      "updatedAt": "2026-06-16T20:02:00Z" }
  ]
}
```

Per operation:

| field | upsert | delete |
|---|---|---|
| `operation` | `"upsert"` | `"delete"` |
| `type` | resource name (consumer-chosen) | same |
| `id` | **required** | **required** |
| `updatedAt` | required (ISO 8601) | required |
| `data` | full resource (includes `id`) | — |

- **One operation for create and edit.** SwiftSync still classifies a local row as a fresh insert
  (never acknowledged) or an edit (acknowledged, since changed) for *its own* bookkeeping, but both go
  on the wire as `upsert`: the server does find-by-`id` → update-else-create. A consumer never has to
  distinguish "does the server already have this?" — that's exactly what the id is for.
- **`data` is the full resource, not a delta.** SwiftSync has no field-level dirty tracking
  (`export(row)` emits the whole object), so an upsert sends every field. The server applies them
  under SwiftSync's payload semantics: a present field is set, an explicit `null` clears it.
- Operations are applied **in array order**.

## Semantics

### Idempotency — keyed on the client `id`

The client may resend an operation it never got a response for (network drop). The server **must not**
create a duplicate. Because `upsert` is keyed on `id`:

- A resent create whose row already exists takes the update branch; an identical `updatedAt` loses the
  LWW tie (below) and returns `stale` — a converged no-op, not a duplicate and not a failure.
- A resent delete on an already-tombstoned (or absent) row returns `applied` — idempotent.

Upserts and deletes are therefore safe to retry indefinitely.

### Conflict — server-authoritative last-writer-wins

The server compares the incoming `updatedAt` with the stored `updatedAt`:

- incoming **newer** ⇒ apply.
- incoming **older or equal** ⇒ the server keeps its version and returns it (`status: "stale"`, with
  the current server row in `server`). SwiftSync adopts the server state locally.

This applies to both `upsert` (when the row already exists) and `delete` — an older delete must not
erase a newer server edit.

### Delete is a soft-delete tombstone

A delete marks the row deleted (server-side) so other clients still learn of the deletion on their
next pull, rather than the row vanishing without a trace. It is not an immediate hard-delete on the
server. (The *client* does hard-delete its own local row once the delete is acknowledged — tombstone
lifecycle is purely a server concern; SwiftSync never manages it.)

**Tombstone retention is the backend's responsibility, not the client's.** A tombstone must be kept
at least as long as your longest plausible client offline window: purge too early and a client that
was offline past the retention period never learns of the deletion and **resurrects the row** on its
next push. Production backends therefore retain tombstones for a bounded window (≥ max offline window)
and purge older ones with a periodic job — the same shape as Amplify DataStore's `BaseTableTTL` or
CouchDB's purge. Pin the retention *capability* (outlast the max offline window), not a magic number
of days.

The `DemoServerSimulator` keeps tombstones indefinitely — it implements no purge, since the demo has
no scheduler and its data is ephemeral. That is a deliberate omission: purge is production backend
guidance, out of scope for the demo and irrelevant to the client.

### Safety: destruction is always explicit

- **`operation` is required.** Missing or unknown ⇒ the operation is **rejected** — the server never
  guesses and never falls back to delete (fail-closed).
- **Only `"delete"` deletes.** A forgotten `data` on an upsert is a rejected upsert — never a delete.

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
    { "operation": "upsert", "id": "0c1f…", "status": "applied" },
    { "operation": "upsert", "id": "8842", "status": "stale",
      "server": { "id": "8842", "title": "Edited elsewhere",
                  "updatedAt": "2026-06-16T20:05:00Z" } },
    { "operation": "delete", "id": "7710", "status": "applied" },
    { "operation": "upsert", "id": "9001", "status": "rejected",
      "code": "validation", "message": "title must not be empty" }
  ],
  "cursor": "2026-06-16T20:02:00Z"
}
```

| `status` | meaning | SwiftSync reaction |
|---|---|---|
| `applied` | written (LWW won, or idempotent re-ack) | confirm; mark the row synced under its `id` |
| `stale` | the client write lost LWW; `server` carries current truth | adopt the server state locally |
| `rejected` | permanent/validation failure | surface `message` (+ `code`) in the failures inbox (discard / edit / retry) |

- Each result echoes the operation's `id` so SwiftSync can map it back onto the right row.
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
2. Per operation: resolve the row by `(type, id)`, apply LWW, upsert / tombstone via the ORM's bulk
   primitive.
3. Return the per-operation `results` + a `cursor`.

Existing per-resource endpoints are untouched — this sits beside them. A real backend scopes every
operation to the authenticated principal and rejects cross-tenant references (`status: "rejected"`);
large pushes are chunked client-side rather than capped by a hard server limit.
