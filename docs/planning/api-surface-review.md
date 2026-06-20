# API Surface Review — Macros & Convention over Configuration

## Why this exists

SwiftSync's public API is **sacred** and must stay **minimal**. The `@Syncable` macro already reads a
rich model surface — `@PrimaryKey`, per-field `@RemoteKey`, `@NotExport`, relationships, the sync
identity — and generates *all* sync plumbing (`make` / `apply` / `applyRelationships` / `export` /
`syncIdentity` / `syncMarkChanged`). For a pure `@Syncable` model the consumer hand-writes **zero** sync
code. That is the bar.

This doc tracks where the surface has drifted from that bar — mostly in the **offline** work — and the
path back, prioritized to work through **one item at a time**.

**Litmus test for every public symbol or consumer-facing requirement:**
> Can the macro derive it from the `@Syncable` surface, or can a convention replace the configuration?
> If yes, it should not be consumer-facing.

**Hard rule:** adding any *new* consumer-facing requirement (a protocol member, a mandatory parameter,
a struct the consumer must construct) is a **hard stop** — discuss before adding. Macros are cheap;
public API is not.

## How to use this doc

Work top-down. Each item: **Context → Current surface → Target → What the macro already knows →
Decision needed → Scope/risk**. Check it off when merged; keep only what's still open. This doc plus
git history is the memory.

## Priority order (highest leverage / lowest risk first)

1. [x] ~~Remove `SyncContext` + local-write `sync(item:)`~~ — **done** (single-object `sync(item:)` applies on main, bulk off-main; `SyncContext` deleted)
2. [x] ~~Macro-generate `SyncOfflineModel`~~ — **superseded**: offline now rides SwiftData History, so there is no `SyncOfflineModel` to generate. Models carry zero offline fields; offline is opted in by marking the identity `@Attribute(.preserveValueOnDeletion)`. See `docs/planning/offline-history-design.md`.
3. [x] ~~Drop `syncFailureReason` from the protocol~~ — **done** (#624: removed from `SyncOfflineModel`)
4. [x] ~~Generalize the inbound LWW timestamp key~~ — **stale**: superseded by the history dirty-set (see §4)
5. [x] ~~Tighten the push response seam~~ — **done**: 5 push structs → 2 (`SyncPendingChanges`, `SyncPushFailure`); `push`→`withPendingChanges` (a `with…` scope) with a `process` closure that returns only `[SyncPushFailure]` (see §5)
6. [x] ~~Unify the three error types into `SyncError`~~ — **done** (#624: `SchemaValidationError` + `ObjectiveCInitializationExceptionError` folded into `SyncError`)
7. [ ] Demote the reactive publishers to `internal`

---

## 1. Remove `SyncContext` + the local-write `sync(item:)` overloads — ✅ done

Resolved via the **convention** "single object → main, bulk → off-main" (chosen over the purist
"local writes never touch sync" — it removed the surface with minimal churn and kept the useful
dict→model apply). `SyncContext` is deleted; the two single-object `sync(item:)` overloads dropped the
`context:` parameter and always apply on `mainContext` (a single row is small, so the immediate
visibility is worth the negligible main-thread cost); bulk `sync(payload:)` stays off-main. All callers
just dropped the `context:` arg. No consumer reasons about `ModelContext` anymore.

---

## 2. Macro-generate the `SyncOfflineModel` conformance

**Context.** Offline models hand-write a 5-member extension:

```swift
extension Task: SyncOfflineModel {
    var syncLocalID: String { id }                        // ← IS the @PrimaryKey — pure duplication
    var syncRemoteID: String? { get/set → remoteID }      // offline-specific
    var syncUpdatedAt: Date { updatedAt }                 // a field the macro could mark/detect
    var syncIsDeleted: Bool { isLocallyDeleted ?? false } // offline-specific
    var syncFailureReason: String? { get/set }            // library failure state — see #3/#6
}
```

**First principles.**
- `syncLocalID` **is** the primary key the macro already requires — never ask for it twice.
- `syncUpdatedAt` — the two-id last-writer-wins design *requires* an updated-date; the consumer declares
  the field regardless. Detect a conventional `updatedAt`, or take an `@SyncUpdatedAt` marker.
- `syncRemoteID` / `syncIsDeleted` are the only genuinely offline-extra concepts → one annotation each.

**Current surface.** `public protocol SyncOfflineModel` with 5 hand-satisfied requirements.

**Target.** `@Syncable` generates the conformance when a model opts into offline. Consumer annotates the
properties it already declares:

```swift
@Syncable @Model final class Task {
    @PrimaryKey var id: String          // → syncLocalID (derived, already required)
    @SyncRemoteID var remoteID: String? // → syncRemoteID
    @SyncTombstone var isLocallyDeleted: Bool // → syncIsDeleted
    var updatedAt: Date                 // → syncUpdatedAt (convention or @SyncUpdatedAt)
}
```

A 5-method extension collapses to **annotations on properties the consumer already declares**, and the
conformance is generated. Consumer hand-writes nothing.

**What the macro already knows.** Primary key, per-field remote keys, fields, identity. **Needs:** new
property annotations (`@SyncRemoteID`, `@SyncTombstone`, optionally `@SyncUpdatedAt`) and emit the
`SyncOfflineModel` extension.

**Decision needed.**
- Annotation names vs pure name convention (detect `remoteID` / `isLocallyDeleted` / `updatedAt`).
- Offline opt-in shape: `@Syncable(offline: true)` vs a separate `@SyncableOffline` vs presence of the
  annotations implying it.

**Scope/risk.** Macro work (`MacrosImplementation` / `SyncableMacro`); biggest leverage. Touches the
macro + demo `Task` + tests; **iOS regression runs on merge** (macro change). Sequence after #1 and in
coordination with #3 (don't generate a field that's being removed).

---

## 3. Drop `syncFailureReason` from `SyncOfflineModel` — ✅ done (#624)

Pure-bubble (#624) removed `syncFailureReason` from `SyncOfflineModel`: the library persists no per-row
failure state — failures bubble up as `withPendingChanges`'s `[SyncPushFailure]` return and the consumer owns any inbox (the
demo annotates its own `@NotExport` field). One fewer hand-written protocol requirement. **Note for #2:**
the macro must not generate this field — it's gone.

---

## 4. Generalize the inbound last-writer-wins timestamp key — 🪦 stale (superseded)

This item assumed the pull does per-row LWW by reading the incoming `updatedAt` from the payload under a
**conventional** key, and worried that a `@RemoteKey`-renamed timestamp would silently skip it.

That mechanism no longer exists. The offline-via-SwiftData-History rework replaced timestamp-based client
LWW with a **history dirty-set**: `applyHonoringLocalEdit` (`API.swift`) keeps any row whose persistent id
is in `offlineDirtyPersistentIDs` (rows with un-pushed local-authored history since the push token) and
applies the server otherwise. The client reads **no timestamp at all** — it's "local-wins-while-pending,"
and the actual timestamp conflict resolution lives on the backend at push time (where the consumer's
`upload` closure owns the payload). So the `@RemoteKey`-rename blind spot can't occur; there's nothing to
generalize. Same fate as #2 (`SyncOfflineModel`), superseded by the same rework.

---

## 5. Tighten the push response seam — ✅ done

**Was.** The push feature exposed **five** public structs — `SyncPushBatch`, `SyncPushFailure`
(+ an `Operation` enum), `SyncPushResponse`, `SyncPushSummary`, `SyncPendingChanges` — and the `upload`
closure took a `SyncPushBatch` and returned a `SyncPushResponse` the consumer assembled by enumerating
*confirmed* ids (a `confirmedLocalIDs` set) plus failures.

**First principle.** The library already hands the consumer the batch, and the client id *is* the
identity the server adopts (an idempotent upsert — no server-assigned ids to map home). So confirmations
are derivable: `confirmed = batch − failures`. Asking the consumer to echo back which ids succeeded was
redundant; only the **failures** carry information the library can't derive.

**Now (5 structs → 2, then +1 for the total-accounting refinement below).**
- `SyncPushBatch` merged into `SyncPendingChanges` — one type is both the return of `pendingChanges(...)`
  and the value `withPendingChanges(...)` hands the `process` closure.
- `SyncPushResponse` **deleted** — `upload` now returns `[SyncPushFailure]` directly.
- `SyncPushFailure` shrank to `{ id, error }` — the `Operation` enum/field went (the operation is
  the library's to know from the batch, not the consumer's to report). Its `id` field was renamed from
  `localID` (a vestige of the deleted two-id `localId`+`remoteId` model); the library deals in one `id`,
  matching the model's `@Attribute(.unique) var id`. The demo's `/sync/upload` wire key followed suit
  (`"localId"` → `"id"`); the backend keeps `public_id` internally, where the int-PK contrast is real.
- `SyncPushSummary` **deleted** — the method returns `[SyncPushFailure]` (the same value the closure
  returns). Its three counts (`insertedCount`/`updatedCount`/`deletedCount`) had no consumer; the demo only
  ever read `.failures`. Counts are derivable by complement if a consumer ever needs them.
- `push(for:in:upload:)` renamed `withPendingChanges(for:in:process:)` — `push` was dishonest (the library
  does no network; unlike `sync`, which *does* the write). The `with…` idiom names what it is: a scope that
  hands you the pending changes, lets your `process` closure do the transport, and commits the token on the
  way out. Pairs with the `pendingChanges` getter (peek vs. process). The `upload` label (a networking
  term) became a trailing closure.
- `inboundAuthor` demoted `public` → `internal` (consumer never referenced it).

**Refinement — total accounting (safety).** Failure-only had a lossy *default*: a `process` closure that
returned `[]` (or omitted a row) asserted "everything succeeded," so a mis-parsed response could silently
advance the token past a rejected row. To make the wrong thing unrepresentable, `process` now returns a
verdict for **every** pending id — `[String: SyncRowOutcome]` (`.confirmed` / `.rejected(error)`) — and
`withPendingChanges` throws `SyncError.incompletePushAccounting` if the map doesn't cover exactly the
pending ids. There's no silence-means-success path; a row can't be dropped or confirmed by omission. This
adds back **one** public type (`SyncRowOutcome`), trading minimal surface for a no-silent-loss guarantee.

Surviving public push surface: `SyncPendingChanges` (in), `SyncRowOutcome` (the per-id verdict), and
`SyncPushFailure` (the `.rejected` rows, returned). The token advances (and inbound history is trimmed)
only on a fully-`.confirmed` pass — same at-least-once semantics.

---

## 6. Unify the three error types into `SyncError` — ✅ done (#624)

Pure-bubble (#624) folded `SchemaValidationError` and `ObjectiveCInitializationExceptionError` into
`SyncError` (`.schemaValidation` / `.containerInitialization` cases) — one error currency, −2 public
structs.

---

## 7. Demote the reactive publishers to `internal`

**Context.** `SyncQueryPublisher` / `SyncModelPublisher` are `public` alongside the `@SyncQuery` /
`@SyncModel` property wrappers. If the wrappers are the only intended entry point, the publishers are
implementation detail.

**Target.** Make them `internal`.

**Decision needed.** Confirm the wrappers are the sole entry point and nothing external constructs a
publisher directly.

**Scope/risk.** Small; predates the offline work; lowest priority.
