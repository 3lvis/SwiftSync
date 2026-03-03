# API Surface Reduction

---

## Macro-expansion visibility constraint

Several symbols must remain `public` because `@Syncable`-generated code expands at the call
site (outside the library module) and calls them by name. `@testable import` does not help
here — it only applies to test targets. The right long-term fix is SPM `package` access, but
that is deferred until there is a clean solution.

**Do not make these internal without a `package`-level solution:**

| Symbol | Why it must stay public |
|---|---|
| `exportEncodeValue(_:options:)` | Macro-generated `exportObject` calls it in client modules |
| `exportSetValue(_:for:into:)` | Same |
| `ExportState.enter(_:)` / `ExportState.leave(_:)` | Same |
| `SyncRelationshipSchemaDescriptor` | Macro-generated `syncRelationshipSchemaDescriptors` constructs it in client modules |
| `syncApplyToOneForeignKey` (all overloads) | Macro-generated `applyRelationships` calls them |
| `syncApplyToManyForeignKeys` (all overloads) | Same |
| `syncApplyToOneNestedObject` (all overloads) | Same |
| `syncApplyToManyNestedObjects` (all overloads) | Same |
| `SyncPayload.required(_:for:)` | Macro-generated `make(from:)` and `apply(_:)` call it |
| `KeyStyle.transform(_:)` | Macro-generated `exportObject` calls it to derive the output key |

---

## Decisions — do not revisit

| Topic | Decision |
|---|---|
| `SyncQueryPublisher` predicate + `relatedTo:through:` inits | **Keep.** Parity with `@SyncQuery` query shapes is the design contract. Demo coverage is not the API contract. |
| `SyncRelationshipOperations` | **Keep.** User-configurable bitmask; tested; part of the documented `sync(...)` API. |
| `package` access for macro helpers | **Defer.** Revisit when there is a clean SPM solution. |

---

## Open work queue

Run the full test suite after each item before proceeding.

- [ ] **1. Remove `protocol SyncRelationshipSchemaIntrospectable`**  
  File: `SwiftSync/Sources/SwiftSync/Core.swift`  
  This protocol declares one requirement — `syncRelationshipSchemaDescriptors` — that already
  exists on `SyncModelable`. It has no conformances anywhere in the codebase (not in tests, the
  Demo, or macro-generated code). It is not documented. Removing it is a safe deletion.  
  TDD order: grep for any reference first to confirm zero usage, then delete the protocol.

- [ ] **2. Audit `ExportRelationshipMode.nested`**  
  File: `SwiftSync/Sources/SwiftSync/Core.swift`  
  The `.nested` case (Rails-style `_attributes` export) has test coverage but no Demo usage and
  no known real-world consumer. Determine whether to keep it as a documented feature or remove
  it to reduce surface area.  
  TDD order: if removing — delete the test cases first, then the case and its handling in
  `exportEncodeValue` / macro-generated output.
