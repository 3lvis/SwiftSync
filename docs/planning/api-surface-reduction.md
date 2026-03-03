# API Surface Reduction

**Status:** In progress

---

## Constraints: macro-expansion visibility

Several symbols are `public` because `@Syncable`-generated code expands into client module scope
and calls them by name. `@testable import` only applies to test targets — it does not help for
production app modules. The right long-term fix is SPM `package` access level, but that is deferred.

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

---

## Decisions — do not revisit

| Topic | Decision |
|---|---|
| `SyncRelationshipOperations` | **Keep as-is.** The OptionSet is tested, not complex, and removing it is not zero risk. |
| Export module extraction (`SwiftSyncExport`) | **Defer.** |
| `SyncModelable` protocol extension methods audit | **Defer.** Needs more analysis before touching. |
| `package` access for macro helpers | **Defer.** Revisit when there's a clean SPM solution. |

---

## Open work queue

Run the full test suite after each item before proceeding.

- [ ] **1. Remove `SyncQueryPublisher` predicate and `relatedTo:through:` inits**  
  File: `SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift`  
  The demo uses only `SyncQueryPublisher(_:in:sortBy:)`. The other three inits have no demo
  usage and no strong external justification.  
  TDD order: delete the corresponding tests from `SyncQueryPublisherTests.swift` first, then
  remove the inits.  
  Inits to remove:
  - `init(_:predicate:in:sortBy:)`
  - `init(_:relatedTo:relatedID:through:in:sortBy:)` — to-one variant
  - `init(_:relatedTo:relatedID:through:in:sortBy:)` — to-many variant

---

## What to keep

| Symbol | Reason |
|---|---|
| `SyncRelationshipOperations` | Decided: keep |
| `SyncContainer(_:ModelContainer, keyStyle:)` | Useful escape hatch |
| `@PrimaryKey`, `@RemotePath`, `@NotExport` | Intentional advanced features |
| `SyncPayload` (the struct) | Required by `SyncUpdatableModel` protocol surface |
| `SyncPayload.value(for:as:)` | Required by protocol surface |
| `SyncPayload.required(_:for:)` | Required — macro-generated and hand-written conformances call it |
| `ExportOptions` | Cannot be internal — macro-generated `exportObject(using:ExportOptions)` references it in client modules |
| `ExportState` | Cannot be internal — macro-generated `exportObject` calls `ExportState.enter/leave` in client modules |
| `exportEncodeValue`, `exportSetValue` | Cannot be internal — same macro constraint |
| `syncApplyToX` family | Cannot be internal — same macro constraint |
