# API Surface Reduction

**Status:** In progress  
**Supersedes:** `demo-coverage-gap.md` (historical record — left intact)

---

## Background

This document tracks the ongoing reduction of SwiftSync's public API surface. The goal is a
minimal, coherent public API where every symbol is either used by the demo or has a strong
external use case. Everything else is internal.

---

## 1. What's already done

### Module consolidation
- `Core`, `SwiftDataBridge`, `Macros`, `TestingKit` merged into single `SwiftSync` target.
  `ObjCExceptionCatcher` (Obj-C, must be separate) and `MacrosImplementation` (macro plugin,
  must be separate) remain as distinct targets.

### Export API simplification (`export-simplification.md` — all 9 items complete)
- `ExportState` internalized — no longer in public protocol or call sites; uses thread-local
  storage internally for cycle detection.
- `ExportKeyStyle` + `SyncInputKeyStyle` unified into single `KeyStyle` enum.
- `SyncContainer.inputKeyStyle` renamed → `SyncContainer.keyStyle`.
- `SyncContainer.dateFormatter` added.
- `exportObject(using:state:)` → `exportObject(using:)` (state fully internal).
- `exportObject(for:container:relationshipMode:)` clean overload added.
- All demo call sites updated.

### `includeNulls` removal
- `ExportOptions.includeNulls` removed entirely. Nil optionals always emit `NSNull`.
  Callers who need to omit a field use `@NotExport`. No per-call override exists.

---

## 2. Constraints: macro-expansion visibility

Several symbols are `public` not because they are intended for external callers, but because
`@Syncable`-generated code expands into client module scope (e.g. the Demo app) and calls them
by name. `@testable import` only applies to test targets — it does not help for production app
modules. The right long-term fix is SPM `package` access level, but that is deferred.

**Do not attempt to make these internal without a `package`-level solution first:**

| Symbol | Why it must stay public |
|---|---|
| `exportEncodeValue(_:options:)` | Macro-generated `exportObject` calls it in client modules |
| `exportSetValue(_:for:into:)` | Same |
| `ExportState.enter(_:)` / `ExportState.leave(_:)` | Same |
| `syncApplyToOneForeignKey` (all overloads) | Macro-generated `syncApplyGeneratedRelationships` calls them |
| `syncApplyToManyForeignKeys` (all overloads) | Same |
| `syncApplyToOneNestedObject` (all overloads) | Same |
| `syncApplyToManyNestedObjects` (all overloads) | Same |
| `SyncPayload.required(_:for:)` | Macro-generated `make(from:)` and `apply(_:)` call it; also a reasonable hand-written conformance primitive |

**Future path:** Add `swift-tools-version: 5.9` (already satisfied) and annotate these symbols
`package` instead of `public`. Requires `Package.swift` `swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]`
or similar — confirm exact SPM config before attempting.

---

## 3. Decisions made — do not revisit

| Topic | Decision |
|---|---|
| `SyncRelationshipOperations` | **Keep as-is.** The OptionSet is tested, not complex, and removing it is not zero risk. |
| Export module extraction (`SwiftSyncExport`) | **Defer.** Opposite direction from the consolidation we just completed. |
| `SyncModelable` protocol extension methods audit | **Defer.** Needs more analysis before touching. |
| `package` access for macro helpers | **Defer.** Skip for now, revisit when there's a clean SPM solution. |

---

## 4. Open work queue

Work through in order. Each item is a discrete, independently executable task.  
Run the full test suite and Demo build after each item before proceeding.

### Tier 1 — Pure visibility changes (zero behavior risk)

- [ ] **1. `SyncDateParser`, `DateType`, `String.dateType()` → internal**  
  File: `SwiftSync/Sources/SwiftSync/SyncDateParser.swift`  
  These are purely internal date-parsing utilities. No macro-generated code calls them.
  Tests access them via `@testable import SwiftSync` (already the case in `DateParserTests.swift`).

- [ ] **2. `SwiftSync.inferToOneRelationship` / `inferToManyRelationship` → internal**  
  File: `SwiftSync/Sources/SwiftSync/API.swift`  
  These are only called from within `API.swift` itself. No external caller needs them.
  Already in a non-`public` extension — confirm visibility and remove `public` if present.

- [ ] **3. `SyncPayload.strictValue`, `SyncPayload.strictRequired` → internal**  
  File: `SwiftSync/Sources/SwiftSync/Core.swift`  
  `strictValue` is only called from library-internal `syncApplyToX` functions.  
  `strictRequired` is only called from `required`'s own implementation.  
  **`SyncPayload.required` stays public** — macro-generated `make(from:)` and `apply(_:)` call
  it in client modules. It is also a legitimate primitive for hand-written conformances.

### Tier 2 — Routing and cleanup (minor external impact)

- [ ] **4. `SwiftSync.sync` and `SwiftSync.export` static methods → internal**  
  File: `SwiftSync/Sources/SwiftSync/API.swift`  
  `SyncContainer` is the intended public entry point. These raw-context overloads exist for
  internal plumbing only.  
  **Required follow-up:** Add `@testable import SwiftSync` to any integration test files that
  call `SwiftSync.sync(...)` or `SwiftSync.export(...)` directly. Currently: `IntegrationTests.swift`,
  `ExportTests.swift`, `RelationshipIntegrityRegressionTests.swift`.

- [ ] **5. Remove `SyncQueryPublisher` predicate and `relatedTo:through:` inits**  
  File: `SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift`  
  The demo uses only `SyncQueryPublisher(_:in:sortBy:)`. The predicate and two `relatedTo:through:`
  inits are not used in the demo and have no strong external justification.  
  Remove from `SyncQueryPublisher.swift` and delete the corresponding tests from
  `SyncQueryPublisherTests.swift` before removing the inits (TDD order).  
  Inits to remove:
  - `init(_:predicate:in:sortBy:)`
  - `init(_:relatedTo:relatedID:through:in:sortBy:)` — to-one variant
  - `init(_:relatedTo:relatedID:through:in:sortBy:)` — to-many variant

---

## 5. What to keep (not candidates for removal)

| Symbol | Reason |
|---|---|
| `SyncRelationshipOperations` | Decided: keep |
| `SyncContainer(_:ModelContainer, keyStyle:)` | Useful escape hatch for apps that build their own `ModelContainer` |
| `@PrimaryKey`, `@RemotePath`, `@NotExport` | Intentional advanced features; mark as advanced in docs |
| `SyncPayload` (the struct) | Required by `SyncUpdatableModel` protocol surface |
| `SyncPayload.value(for:as:)` | Required by protocol surface; callers read payload values in conformances |
| `SyncPayload.required(_:for:)` | Required — macro-generated and hand-written conformances call it |
| `ExportOptions` | Cannot be internal — macro-generated `exportObject(using:ExportOptions)` references it in client modules |
| `ExportState` | Cannot be internal — macro-generated `exportObject` calls `ExportState.enter/leave` in client modules |
| `exportEncodeValue`, `exportSetValue` | Cannot be internal — same macro constraint |
| `syncApplyToX` family | Cannot be internal — same macro constraint |

---

## 6. Files affected by open work

| File | Items |
|---|---|
| `SwiftSync/Sources/SwiftSync/SyncDateParser.swift` | Item 1 |
| `SwiftSync/Sources/SwiftSync/API.swift` | Items 2, 4 |
| `SwiftSync/Sources/SwiftSync/Core.swift` | Item 3 |
| `SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift` | Item 5 |
| `SwiftSync/Tests/IntegrationTests/IntegrationTests.swift` | Item 4 (`@testable import`) |
| `SwiftSync/Tests/IntegrationTests/ExportTests.swift` | Item 4 (`@testable import`) |
| `SwiftSync/Tests/IntegrationTests/RelationshipIntegrityRegressionTests.swift` | Item 4 (`@testable import`) |
| `SwiftSync/Tests/IntegrationTests/SyncQueryPublisherTests.swift` | Item 5 (remove tests first) |
