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
4. [ ] Generalize the inbound LWW timestamp key — convention today, macro later
5. [ ] Tighten the push response seam (5 public structs)
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
failure state — failures bubble up via `SyncPushSummary.failures` and the consumer owns any inbox (the
demo annotates its own `@NotExport` field). One fewer hand-written protocol requirement. **Note for #2:**
the macro must not generate this field — it's gone.

---

## 4. Generalize the inbound last-writer-wins timestamp key

**Context.** The pull's per-row LWW (stops a refresh from clobbering an un-pushed local edit, merged in
#625) reads the incoming timestamp from the payload under the **conventional** `updatedAt` / `updated_at`
key. An offline model whose timestamp uses a `@RemoteKey` rename **silently skips LWW** (degrades to a
plain apply — i.e. pre-#625 behavior). This is convention-over-configuration working *today* with one
blind spot.

**Target.** Once #2 exists, the macro surfaces the model's timestamp remote key (ties to
`@SyncUpdatedAt`), and LWW reads the right key — no convention blind spot, still zero consumer config.

**Decision needed.** Only act when a real consumer hits the rename case; fold into #2's macro work rather
than adding standalone API.

**Scope/risk.** Internal; ties to #2. No standalone public API.

---

## 5. Tighten the push response seam

**Context.** The push feature exposes five public structs — `SyncPushBatch`, `SyncPushFailure`
(+`Operation`), `SyncPushResponse`, `SyncPushSummary`, `SyncPendingChanges`. The consumer hand-maps its
server's JSON into a `SyncPushResponse` (three id sets — `assignedRemoteIDs` / `confirmedUpdateLocalIDs`
/ `confirmedDeleteLocalIDs` — plus `failures`). Some mapping is inherent (server shapes vary), but the
return shape of the `upload` closure deserves a first-principles pass.

**Target.** Review whether the closure's return can be smaller or library-derived (e.g. derive
confirmations from the batch + assigned ids rather than asking the consumer to enumerate three sets).

**Decision needed.** Needs a design pass; lower leverage than #1–#2 — don't churn the seam without a
clear reduction.

**Scope/risk.** Public API change to the push seam; medium.

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
