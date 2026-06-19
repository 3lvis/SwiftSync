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

1. [ ] Remove `SyncContext` + local-write `sync(item:)` — surface removal, self-contained
2. [ ] Macro-generate `SyncOfflineModel` — the flagship "magic" move
3. [ ] Drop `syncFailureReason` from the protocol — rides pure-bubble (#624)
4. [ ] Generalize the inbound LWW timestamp key — convention today, macro later
5. [ ] Tighten the push response seam (5 public structs)
6. [ ] Unify the three error types into `SyncError` — rides #624
7. [ ] Demote the reactive publishers to `internal`

---

## 1. Remove `SyncContext` + the local-write `sync(item:)` overloads

**Context.** `SyncContext` (`.main` / `.background`) plus a *mandatory* `context:` parameter on the two
single-object `sync(item:…)` overloads was added (it replaced an earlier `runOnMain: Bool`) to route a
*local* write onto `mainContext` (immediate visibility) versus an *inbound* sync onto a background
context. This leaks a `ModelContext`-routing decision into the public API. **A consumer should never
have to reason about which `ModelContext` a write lands in — that is the library's job.**

**First principles.** The offline design is *"pending changes are a query over the store — no
save-interception."* So a local write is just **mutate your `@Model` on `mainContext` and save** (plain
SwiftData, already visible); the `pendingChanges` query then detects it (insert = `syncRemoteID == nil`,
edit = `syncUpdatedAt > cursor`, delete = tombstone). **Local writes don't need to go through SwiftSync
at all.** Inbound sync (`sync(payload:)`) is the only thing that needs a context, and it should always
run off-main *internally* with no consumer choice.

**Current surface.** `public enum SyncContext`; `2×` `public func sync(item:…, context: SyncContext)`.

**Target.** Delete `SyncContext` and the local-write `sync(item:)` path. Inbound sync picks its context
internally. Document "local writes = direct model mutation + save" as the supported pattern.

**Evidence it's a convenience, not a necessity.** The demo is already inconsistent: offline *people*
edits mutate the model directly (`applyLocalPeople`), while offline *create/update* route through
`sync(item:context:.main)` purely to reuse the dict→model `apply` mapping.

**Decision needed.** Confirm no apply-time behavior (relationship resolution, field coercion) that local
create/update actually depend on. If a dict→model convenience is still wanted, provide it without
exposing a context (or have the consumer set fields directly).

**Scope/risk.** Small, self-contained; removes public surface this work introduced. Touches
`SyncContainer` + the demo engine's offline `createTask`/`updateTask`. Existing offline tests must stay
green. **Recommended first** — highest confidence, removes surface, no macro work.

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

## 3. Drop `syncFailureReason` from `SyncOfflineModel`

**Context.** `syncFailureReason` is library-persisted per-row failure state. The pure-bubble redesign
(PR #624, not yet merged) establishes that **the library persists no per-row failure state** — failures
bubble up via `SyncPushSummary.failures` and the *consumer* owns any inbox.

**Target.** Remove the requirement from the protocol. A consumer that wants a failures inbox annotates
its own demo-owned field — not a SwiftSync requirement.

**Dependency.** Rides #624. When that merges, this requirement is gone. **Coordinate with #2** — do not
macro-generate a field that #624 is deleting.

**Decision needed.** Merge order of #624 relative to the #2 macro work.

**Scope/risk.** Mostly carried by #624; the macro work in #2 must assume it's gone.

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

## 6. Unify the three error types into `SyncError`

**Context.** `SyncError` + `SchemaValidationError` + `ObjectiveCInitializationExceptionError` are all
public on `master`. One error currency is enough.

**Target.** Collapse to `SyncError` (the #624 branch already does this).

**Dependency.** Rides #624.

**Scope/risk.** Surface *reduction*; low risk; carried by #624.

---

## 7. Demote the reactive publishers to `internal`

**Context.** `SyncQueryPublisher` / `SyncModelPublisher` are `public` alongside the `@SyncQuery` /
`@SyncModel` property wrappers. If the wrappers are the only intended entry point, the publishers are
implementation detail.

**Target.** Make them `internal`.

**Decision needed.** Confirm the wrappers are the sole entry point and nothing external constructs a
publisher directly.

**Scope/risk.** Small; predates the offline work; lowest priority.
