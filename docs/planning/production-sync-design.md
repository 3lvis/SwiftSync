# Production Sync Contract

SwiftSync reconciles JSON payloads into SwiftData and exposes locally authored history for outbound
processing. The app owns transport, authentication, retry policy, and any user-facing failure inbox.

## Boundary

SwiftSync owns:

- inbound reconciliation and relationship application;
- identification of local inserts, updates, and deletes through SwiftData History;
- protection of unpushed local changes from inbound overwrite or pruning;
- the pushed-history token and its all-success advancement rule;
- transport-independent errors and per-row rejection values.

The consumer owns:

- pull and upload network calls;
- serialization of pending ids into its backend's request format;
- retry, backoff, `Retry-After`, and authentication refresh;
- backend conflict policy and interpretation of backend responses;
- persistence and presentation of a failures inbox.

SwiftSync has no concrete transport dependency.

## Identity

There is one external row identity. The client's stable string `id` is the value sent in pull payloads,
REST routes, and upload operations. A controlled backend adopts a client-minted id as its unique
`public_id`; server-created rows receive a server-minted `public_id` before reaching the client. A
backend may keep a separate internal primary key for joins, but it never exposes that key.

There is no `localId`/`remoteId` pair and no identity rewrite after an upload. Retrying an upsert after a
lost response addresses the same unique id and must converge on the existing server row.

## Local change detection

Offline push is opt-in per model by marking its string sync identity
`@Attribute(.unique, .preserveValueOnDeletion)`. SwiftSync validates this requirement before reading or
processing pending changes; without it a delete tombstone cannot preserve the id and the deletion could
be lost.

SwiftData History is the queue:

- local writes use the store's default transaction author;
- inbound reconciliation uses SwiftSync's inbound author;
- transactions after the model's last-pushed token are reduced into inserts, updates, and deletes;
- an insert followed by updates remains an insert;
- an update followed by deletion becomes a delete;
- an insert deleted before its first push disappears because the server never observed it.

Local edits must use ordinary SwiftData writes. Calling inbound `sync(item:)` for a local edit stamps it
as inbound and intentionally excludes it from pending changes.

## Pull while local changes are pending

For offline-enabled models, inbound reconciliation computes the locally dirty persistent identifiers
before applying a payload. A dirty row is not overwritten or removed merely because the server payload
omits it. Once its local history is successfully pushed and the token advances, normal server-authority
reconciliation resumes.

Models without `.preserveValueOnDeletion` retain the ordinary pull contract: the server payload is
authoritative.

## Push seam

`pendingChanges(for:in:)` lets a consumer inspect the pending ids.

`withPendingChanges(for:in:process:)` captures one history batch and passes a `SyncPendingChanges` value
to the consumer's async closure. The closure performs transport and returns only rejected rows as
`[SyncPendingChangesFailure]`. Every id not returned as a failure is confirmed by complement.

The pushed token advances only when the closure returns no failures. It advances to the newest token
captured before the await, never to the live history head, so a write that lands during upload remains
pending for the next pass. Throws and partial rejection leave the token unchanged.

## Failure contract

SwiftSync throws one `SyncError` currency for invalid payloads, cancellation, schema validation, and
container initialization. Transport errors pass through the consumer's closure.

A backend rejection is partial-success data, not a thrown library error. `SyncPendingChangesFailure`
contains the rejected id and the consumer's own error value. SwiftSync persists no failure reason or
retry category on application models. The demo chooses to copy returned failures onto its own
`@NotExport` field; that is application policy, not library behavior.

## Conflict contract

SwiftSync does not impose a backend conflict algorithm. The demo backend uses server-authoritative
whole-record last-writer-wins based on `updatedAt`: older or equal writes are stale, newer writes apply,
and a newer upsert may revive a tombstone. A stale response carries the server row, which the demo
applies inbound and treats as resolved.

Production backends must make upserts atomic and authorize every operation by principal and ownership.
Knowing or minting an id is not authorization.

## Still open

- App-owned retention for already-pushed local history, triggered by production evidence and coordinated
  across every history consumer.
- Offline-safe queue migration/versioning once shipped consumers have persisted pending changes.
- A multi-consumer lifecycle event stream for observability.
- Pull/cursor protocol research only if that contract is hardened beyond the current consumer-owned
  transport boundary.
