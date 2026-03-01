# Export API Simplification

**Status:** Complete  
**Priority:** High — blocks clean demo usage of export at call sites

---

## Problem

The current export call site requires three pieces of boilerplate that callers should never need to see:

```swift
var exportState = ExportState()
let options = ExportOptions(relationshipMode: .none, includeNulls: false)
let body = task.exportObject(using: options, state: &exportState)
```

`ExportState` is an internal cycle-detection mechanism. `keyStyle` and `dateFormatter` in `ExportOptions` are container-level concerns already configured when `SyncContainer` is initialized. None of this belongs at the call site.

---

## Changes

### 1. Make `ExportState` internal — Priority: High

**Current:** `ExportState` is a `public struct` passed as `inout` to `exportObject`. Callers must construct and manage it.

**Why it exists:** Cycle detection for recursive relationship export. When `exportObject` recurses into related objects (`.array` / `.nested` mode), `ExportState` tracks which objects are currently being visited via `persistentModelID` to prevent infinite loops on bidirectional relationships.

**Why it should be internal:** Callers never need to inspect or control `ExportState`. It is a pure implementation detail of the recursive traversal. Exposing it as `inout` forces every call site to allocate and pass a value it has no use for — especially for `relationshipMode: .none` where relationships are never traversed and `ExportState` is entirely dead weight.

**Proposed change:**
- Make `ExportState` `internal` (or `private` to the module).
- Remove `state: inout ExportState` from the `exportObject` protocol requirement.
- The generated `exportObject` implementation allocates its own `ExportState` internally and passes it through recursive calls.
- Public signature becomes: `func exportObject(using options: ExportOptions) -> [String: Any]`

**Impact:** Breaking change to `SyncUpdatableModel` protocol. All `@Syncable` models are affected (generated code). Any hand-written `SyncUpdatableModel` conformances that override `exportObject` must be updated. `ExportTests` must be updated.

**Note on `relationshipMode`:** Even with `ExportState` internal, recursive relationship export still works — the generated `exportObject` passes the state through recursive child calls internally. The public API just stops leaking it.

---

### 2. Move `keyStyle` to `SyncContainer` — Priority: High

**Current:** `ExportOptions.keyStyle: ExportKeyStyle` (`.snakeCase` / `.camelCase`) is a per-call option.

**Why it should move:** `SyncContainer` already owns `inputKeyStyle: SyncInputKeyStyle` which controls how incoming API keys are translated on the read (sync) path. The export (write) path must use the same key convention — if the API speaks snake_case in, it speaks snake_case out. A per-call `keyStyle` means callers can accidentally export in the wrong case, and every call site must repeat the same value.

**Proposed change:**
- Remove `keyStyle` from `ExportOptions`.
- Rename `SyncContainer.inputKeyStyle` → `SyncContainer.keyStyle` (it governs both directions).
- Add a `SyncContainer`-aware `exportObject` overload (or make the container available via the call site) so the export path reads `keyStyle` from the container.
- For the `SwiftSync.export(as:in:using:)` static methods, derive `keyStyle` from the `ModelContext`'s container if possible, or require passing the container explicitly.
- `ExportKeyStyle` and `SyncInputKeyStyle` should be unified into a single `KeyStyle` enum (they represent the same concept — snake_case vs camelCase — just named differently because they were designed independently).

**Open question:** `exportObject` is currently called on the model object directly with no reference to `SyncContainer`. Two options:
- A) Add a `SyncContainer`-aware overload: `task.exportObject(for: syncContainer, relationshipMode: .none, includeNulls: false)` — clean call site, container provides `keyStyle` and `dateFormatter`.
- B) Keep `keyStyle` in `ExportOptions` but derive the default from `SyncContainer` when using the container-level export entry point — callers using the low-level `exportObject` directly still pass it explicitly.

**Recommendation:** Option A. It makes the container the natural entry point for export, consistent with how it's the entry point for sync.

---

### 3. Move `dateFormatter` to `SyncContainer` — Priority: Medium

**Current:** `ExportOptions.dateFormatter: DateFormatter` defaults to `ExportOptions.defaultDateFormatter()` — an ISO8601 formatter with millisecond precision.

**Why it should move:** The date format is an API contract, not a per-request decision. The same contract governs both read (sync) and write (export). Configuring it per-call is redundant and risks inconsistency between the formatter used to parse incoming dates and the one used to serialize outgoing ones.

**Proposed change:**
- Add `exportDateFormatter: DateFormatter` (or just `dateFormatter`) to `SyncContainer`.
- Default to the same ISO8601 format currently used by `ExportOptions.defaultDateFormatter()`.
- Remove `dateFormatter` from `ExportOptions`.
- `ExportOptions.defaultDateFormatter()` becomes internal.

---

### 4. `relationshipMode` — keep per-call, clarify semantics — Priority: Low

**Current:** `ExportOptions.relationshipMode: ExportRelationshipMode` (`.array` / `.nested` / `.none`).

**Why it stays per-call:** Different endpoints have genuinely different relationship serialization needs. A POST body for a single resource typically wants `.none` (no relationship traversal). A bulk export for a different system might want `.array` or `.nested`. This varies by call, not by container.

**Clarification needed on recursiveness:**
- `.none` — relationships are never traversed. `ExportState` cycle guard is irrelevant. Output contains only scalar fields.
- `.array` — to-many relationships are serialized as arrays of exported child objects. Recursive. `ExportState` cycle guard is active.
- `.nested` — relationships are serialized as `<key>_attributes` dicts (Rails-style nested attributes). Recursive. `ExportState` cycle guard is active.

For the API request body use case (create / update), `.none` is almost always correct — the server receives scalar IDs for relationships, not nested objects. `.array` / `.nested` are for export-to-file, share sheet, or Rails-style nested create scenarios.

**No change required here** — just document the semantics clearly.

---

### 5. `includeNulls` — keep per-call — Priority: Low

**Current:** `ExportOptions.includeNulls: Bool`.

**Why it stays per-call:** Whether to serialize `null` for missing optional fields depends on the endpoint's partial-update contract. Sending explicit `null` means "clear this field." Omitting the key means "no-op." These are different API intents that vary per request.

**No change required.**

---

## Resulting call site (after all changes)

```swift
// Before
var exportState = ExportState()
let options = ExportOptions(relationshipMode: .none, includeNulls: false)
let body = task.exportObject(using: options, state: &exportState)

// After
let body = task.exportObject(for: syncContainer, relationshipMode: .none, includeNulls: false)
```

Or for the no-relationships, include-nulls default case:

```swift
let body = task.exportObject(for: syncContainer)
```

---

## Execution checklist

- [x] 1. Make `ExportState` internal — update protocol, generated code, `ExportTests`, hand-written conformances
- [x] 2. Unify `ExportKeyStyle` and `SyncInputKeyStyle` into a single `KeyStyle` enum
- [x] 3. Move `keyStyle` to `SyncContainer`, rename `inputKeyStyle` → `keyStyle`
- [x] 4. Move `dateFormatter` to `SyncContainer`
- [x] 5. Add `exportObject(for:relationshipMode:includeNulls:)` overload on `SyncUpdatableModel`
- [x] 6. Update `SwiftSync.export(as:in:using:)` static methods to derive `keyStyle` and `dateFormatter` from container
- [x] 7. Update all demo call sites
- [x] 8. Update `ExportTests` and `demo-coverage-gap.md`
- [x] 9. Consolidate module structure: Core + SwiftDataBridge + Macros + TestingKit → single SwiftSync target
