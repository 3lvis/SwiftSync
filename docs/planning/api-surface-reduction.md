# API Surface Reduction

---

## Macro-expansion visibility constraint

Several symbols must remain `public` because `@Syncable`-generated code expands at the call
site (outside the library module) and calls them by name. `@testable import` does not help
here — it only applies to test targets. The right long-term fix is SPM `package` access, but
that is deferred until there is a clean solution.

**Do not make these internal without a `package`-level solution:**

| Symbol                                            | Why it must stay public                                                             |
| ------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `exportEncodeValue(_:options:)`                   | Macro-generated `exportObject` calls it in client modules                           |
| `exportSetValue(_:for:into:)`                     | Same                                                                                |
| `ExportState.enter(_:)` / `ExportState.leave(_:)` | Same                                                                                |
| `SyncRelationshipSchemaDescriptor`                | Macro-generated `syncRelationshipSchemaDescriptors` constructs it in client modules |
| `syncApplyToOneForeignKey` (all overloads)        | Macro-generated `applyRelationships` calls them                                     |
| `syncApplyToManyForeignKeys` (all overloads)      | Same                                                                                |
| `syncApplyToOneNestedObject` (all overloads)      | Same                                                                                |
| `syncApplyToManyNestedObjects` (all overloads)    | Same                                                                                |
| `SyncPayload.required(_:for:)`                    | Macro-generated `make(from:)` and `apply(_:)` call it                               |
| `KeyStyle.transform(_:)`                          | Macro-generated `exportObject` calls it to derive the output key                    |

---

## Decisions — do not revisit

| Topic                                                       | Decision                                                                                                       |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `SyncQueryPublisher` predicate + `relatedTo:through:` inits | **Keep.** Parity with `@SyncQuery` query shapes is the design contract. Demo coverage is not the API contract. |
| `SyncRelationshipOperations`                                | **Keep.** User-configurable bitmask; tested; part of the documented `sync(...)` API.                           |
| `package` access for macro helpers                          | **Defer.** Revisit when there is a clean SPM solution.                                                         |

---

## Open work queue

Run the full test suite after each item before proceeding.

- [x] **1. Remove `protocol SyncRelationshipSchemaIntrospectable`**  
  Dead protocol — no conformances, no callers, requirement already on `SyncModelable`. Deleted.

- [ ] **2. Decide: keep or remove `ExportRelationshipMode.nested`**  
  File: `SwiftSync/Sources/SwiftSync/Core.swift`  
  Full analysis in `docs/planning/export-nested-mode.md`. Two options:  
  - **Keep** — add a `Comment` model to the demo (see the doc for the full scenario). Gives
    `.nested` real end-to-end coverage and justifies its place in the API surface.  
  - **Remove** — no current consumer, demo or otherwise. TDD order: delete the `.nested`
    assertions from `testExportRelationshipModesArrayNestedNone` in `SyncExportTests.swift`
    first, then remove the case from `ExportRelationshipMode` in `Core.swift` and the
    `case .nested:` branches from `MacrosImplementation/SyncableMacro.swift`.
