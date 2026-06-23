# Upload Endpoint Contract

The upload endpoint is the backend half of SwiftSync's offline push seam. It sits beside ordinary CRUD
routes; SwiftSync does not call it directly. The consumer maps `SyncPendingChanges` ids into this request,
interprets the response, and returns rejected rows from `withPendingChanges`.

## Endpoint

```text
POST /sync/upload
```

One request carries an ordered list of pending operations. Results are per operation, so one rejected row
does not block unrelated rows.

## Identity

Every operation is addressed by one stable external `id`:

- A client-created row uses its client-minted id.
- A server-created row receives a server-minted external id before any client sees it.
- The backend stores that value in a unique `public_id` and exposes it as `id` in every API.
- Any backend-internal primary key remains private and may be used for joins and foreign keys.

There is no `localId`, `remoteId`, or post-upload identity rewrite. On first upload the backend adopts the
client id as `public_id`; a retry addresses the same unique row.

## Request

```json
{
  "operations": [
    {
      "operation": "upsert",
      "type": "tasks",
      "id": "0c1f…",
      "updatedAt": "2026-06-16T20:00:00Z",
      "data": {
        "id": "0c1f…",
        "title": "Draft",
        "description": null,
        "state": { "id": "todo" }
      }
    },
    {
      "operation": "delete",
      "type": "tasks",
      "id": "7710",
      "updatedAt": "2026-06-16T20:02:00Z"
    }
  ]
}
```

| Field | Upsert | Delete |
|---|---|---|
| `operation` | `"upsert"` | `"delete"` |
| `type` | required resource name | required resource name |
| `id` | required stable external id | required stable external id |
| `updatedAt` | required ISO-8601 timestamp | required ISO-8601 timestamp |
| `data` | required full resource | absent |

An upsert represents both creation and update. The server resolves `public_id` and atomically inserts or
updates. `data` is a complete resource rather than a field delta: present values replace server values,
explicit `null` clears a nullable field, and validation rejects malformed required fields.

Only an explicit `"delete"` operation deletes. A missing or unknown operation and an upsert without
`data` are rejected; destructive behavior is never inferred from omission.

## Response

```json
{
  "results": [
    { "operation": "upsert", "id": "0c1f…", "status": "applied" },
    {
      "operation": "upsert",
      "id": "8842",
      "status": "stale",
      "server": {
        "id": "8842",
        "title": "Edited elsewhere",
        "updated_at": "2026-06-16T20:05:00Z"
      }
    },
    { "operation": "delete", "id": "7710", "status": "applied" },
    {
      "operation": "upsert",
      "id": "9001",
      "status": "rejected",
      "code": "validation",
      "message": "title must not be empty"
    }
  ],
  "cursor": "2026-06-16T20:02:00Z"
}
```

| Status | Meaning | Consumer action |
|---|---|---|
| `applied` | The operation was accepted or already converged. | Return no failure. |
| `stale` | Server conflict policy kept its row. | Apply `server` inbound and return no failure. |
| `rejected` | Validation or authorization rejected this row. | Return `SyncPendingChangesFailure`. |

Every result echoes `operation` and `id`. `rejected` includes a human-readable `message` and may include
a stable backend `code`; SwiftSync treats both as consumer-owned data. The demo returns a response cursor,
but SwiftSync's local pushed-history token is internal and independent. A production consumer may pair an
opaque server cursor with its pull protocol.

## Idempotency and concurrency

Upsert must be atomic on unique `public_id`. A separate `SELECT` followed by `INSERT` is insufficient:
two requests can both observe absence and race. Use the backend's conflict-aware upsert primitive, or a
transaction that recovers the uniqueness conflict as an update.

The client advances its pushed-history token only after a clean result set. A transport failure may
therefore resend the same operation. Repetition must converge:

- repeated upsert targets the same `public_id` and never creates a duplicate;
- repeated delete of an absent or already tombstoned row returns `applied`;
- an equal timestamp follows the backend's deterministic tie policy.

## Demo conflict policy

The demo applies whole-record last-writer-wins:

- incoming timestamp newer than stored timestamp: apply;
- incoming timestamp older or equal: return `stale` with the current server row;
- delete records its logical timestamp on a tombstone;
- an upsert newer than the tombstone revives the row;
- an older or equal upsert leaves the tombstone and returns `stale`.

This is the demo's backend policy, not a conflict algorithm imposed by SwiftSync.

## Tombstone retention

Server deletes are tombstones so clients that were offline can still learn about them on pull. A
production backend must retain tombstones longer than its maximum supported offline window; purging too
early allows an old client to resurrect deleted data. The demo keeps tombstones indefinitely because it
has ephemeral data and no retention scheduler.

## Authorization

The backend must scope every lookup, upsert, delete, and referenced relationship to the authenticated
principal. A unique or hard-to-guess id prevents accidental duplication; it does not authorize access.
