# Public API Surface — the contract

The authoritative map of what `SwiftSync` (the library target, `SwiftSync/Sources/SwiftSync`) exposes,
and **why**. Its companion [`api-surface-review.md`](api-surface-review.md) tracks *shrinking* the
surface; this doc records the surface that should *stay*, so nothing is demoted by accident.

The surface is **sacred and minimal**: a pure `@Syncable` model needs the consumer to hand-write zero
sync code. Every `public` symbol falls into one of the buckets below. Before adding a `public`, it must
fit one — otherwise it's accidental and should be `internal`.

## 1. Consumer API — what a consumer calls directly

- `SwiftSync` — root namespace for the top-level static API.
- `SyncContainer` — the entry point: both inits, `modelContainer` / `mainContext` / `keyStyle` /
  `dateFormatter`, the `sync(payload:…)` / `sync(item:…)` overloads (incl. parent-scoped), `export(_:)`.
- `SwiftSync.pendingChanges(for:in:)`, `SwiftSync.push(for:in:upload:)`, `SwiftSync.inboundAuthor` —
  the offline push entry points.
- `KeyStyle`, `SyncError` — configuration + the single error currency.
- `SyncPayload`, `SyncPayloadConvertible` — payload wrapper + the opt-in "convert my type to a payload".
- Macro attributes: `@Syncable`, `@PrimaryKey`, `@RemoteKey`, `@NotExport` (declared in the macro module).

## 2. Macro-support — PUBLIC BY CONTRACT (must never be demoted)

These are `public` **only** because the `@Syncable` macro's generated code calls or conforms to them, and
that generated code lives in the **consumer's** module. Demoting any of them is a source break for *every*
consumer, even though nothing in this repo outside the macro calls them. They are marked at their
declaration in `Core.swift` with a `PUBLIC BY CONTRACT` comment — do not remove the marker or the `public`.

| Symbol | Kind | Why public |
|---|---|---|
| `SyncModelable` | protocol | generated extension conforms to it; all members are implemented in the consumer module |
| `SyncUpdatableModel` | protocol | generated extension conforms to it (`make`/`apply`/`applyRelationships`/`export`/`syncMarkChanged`) |
| `SyncRelationshipSchemaDescriptor` | struct | the macro builds an array of these for `syncRelationshipSchemaDescriptors` |
| `SyncRelationshipOperations` | struct (OptionSet) | named in the generated `applyRelationships(...)` signature/body |
| `ExportState` | enum | generated `export(...)` calls `enter`/`leave` for cycle detection |
| `exportEncodeValue(_:dateFormatter:)` | func | generated `export(...)` encodes each scalar through it |
| `exportSetValue(_:for:into:)` | func | generated `export(...)` writes (nested) keys through it |
| `syncApplyToOneForeignKey` | func (overloads) | generated relationship-apply emits calls (to-one FK) |
| `syncApplyToManyForeignKeys` | func (overloads) | generated relationship-apply emits calls (to-many FK) |
| `syncApplyToOneNestedObject` | func (overloads) | generated relationship-apply emits calls (to-one nested) |
| `syncApplyToManyNestedObjects` | func (overloads) | generated relationship-apply emits calls (to-many nested) |

Verification: each name appears in the emitted code in `SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift`
(grep the macro for the symbol). Keep that true — if the macro stops emitting one, *then* it can be demoted.

## 3. Reactive reads (SwiftUI) — consumer-facing

- `@SyncQuery` / `@SyncModel` — the property wrappers consumers use in SwiftUI.
- `SyncQueryPublisher` / `SyncModelPublisher` — `@Observable` non-property-wrapper equivalents.

(Whether the two publishers stay public or collapse behind the wrappers is open as
`api-surface-review.md` item 7 — a deliberate decision, not an accidental-public question.)

## 4. Offline push seam — consumer constructs / reads

`SyncPendingChanges` (read), `SyncPushBatch` (read in the upload closure), `SyncPushResponse` +
`SyncPushFailure` (consumer constructs in its upload closure), `SyncPushSummary` (read from `push()`).
Tightening these five is open as `api-surface-review.md` item 5.

## Enforcement

- **Now (human):** the `PUBLIC BY CONTRACT` markers in `Core.swift` + this doc.
- **At first tag (automated):** the release-time `swift package diagnose-api-breaking-changes` gate
  (roadmap Phase 6) will flag any accidental demotion of these symbols against the published baseline.
