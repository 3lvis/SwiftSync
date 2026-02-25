# Protocol Collapse & Surface Reduction — Work Log

## What Was Done

### Phase 1: Protocol Hierarchy Collapse

Removed three thin/redundant protocols and merged them into the remaining ones. No behavior changes — only the public protocol surface shrinks.

**Removed protocols:**
- `SyncQuerySortableModel` → folded `syncSortDescriptor(for:)` + `syncSortDescriptors(for:)` into `SyncModelable` (default impls return `nil`/`[]`)
- `SyncRelationshipSchemaIntrospectable` → folded `syncRelationshipSchemaDescriptors` into `SyncModelable` (default impl returns `[]`)
- `SyncRelationshipUpdatableModel` → merged both `applyRelationships` signatures into `SyncUpdatableModel` with defaults (`return false`, delegates to 2-arg)

**Files changed:** `Core/Core.swift`, `Macros/SyncableMacro.swift`, `MacrosImplementation/SyncableMacro.swift`, `SwiftSync/ReactiveQuery.swift`, `SwiftSync/SyncContainer.swift`, `SwiftDataBridge/API.swift`, test files.

---

### Phase 2: Surface Minimization (based on real usage)

**Stated usage surface:** `@Syncable` macro + `SyncQuery` in views + `export()`.

**Removed:** Entire `ParentScopedModel` protocol and the parent-scoped sync path:
- Deleted `ParentScopedModel` from `Core.swift`
- Deleted `sync<Model: ParentScopedModel>` and `sync<Model, Parent: PersistentModel>` public overloads from `SyncContainer.swift`
- Deleted the private `sync<Model, Parent>(parentRelationship:isGlobal:...)` ~150-line implementation from `API.swift`
- Deleted private helpers: `resolveParent`, `ParentRelationshipCandidate`, `syncIdentityHasUniqueAttribute`, `scopedIdentityKey`
- Deleted 13 parent-scoped test functions and associated model classes from `IntegrationTests.swift`
- Deleted `testExportParentScopedOnlyExportsThatParentsChildren` and `extension ExportChild: ParentScopedModel` from `ExportTests.swift`

**Access level change:** `SwiftSync.sync()` and inference helpers (`inferToOneRelationship`, `inferToManyRelationship`) downgraded from `public` to `package` (Swift 6.2 feature), since they're only called from within the package (`SyncContainer`, `ReactiveQuery`). `export()` stays `public`.

---

### Items That Cannot Be Made Internal (for user review)

These are public because `@Syncable`-generated code calls them from the **user's module**, which is outside the package boundary:

| Symbol | Reason |
|--------|--------|
| `syncApplyToOneForeignKey` (4 overloads) | Called from macro-generated `applyRelationships` |
| `syncApplyToManyForeignKeys` (2 overloads) | Called from macro-generated `applyRelationships` |
| `syncApplyToOneNestedObject` (2 overloads) | Called from macro-generated `applyRelationships` |
| `syncApplyToManyNestedObjects` (2 overloads) | Called from macro-generated `applyRelationships` |
| `exportEncodeValue` | Called from macro-generated `exportObject` |
| `exportSetValue` | Called from macro-generated `exportObject` |
| `SyncRelationshipOperations` | Protocol requirement type, `SyncContainer.sync()` parameter |
| `SyncMissingRowPolicy` | `SyncContainer.sync()` parameter |

---

## 3 Remaining Failing Tests (Blocked — Investigation In Progress)

### Root Cause Identified

`syncSortDescriptor(for:)` and `syncRelationshipSchemaDescriptors` were moved to **extension defaults only** (not formal protocol requirements) during Phase 1. This breaks dynamic dispatch when called through a generic or existential context:

- Inside `syncSortDescriptors(for:)` (in `SyncModelable` extension), `syncSortDescriptor` dispatches statically → always returns `nil` (default) instead of the macro-generated concrete implementation
- Inside `SyncContainer._schemaRelationships`, `introspectable.syncRelationshipSchemaDescriptors` on `any SyncModelable.Type` also dispatches statically → always returns `[]`

### Failures

**`SyncQuerySortSugarTests.testGeneratedSortDescriptorsApplyStoreLevelOrdering`**
- `SortSugarRecord.syncSortDescriptors(for: [\.displayName, \.id])` returns `[]` instead of real `SortDescriptor`s
- Expected: `["Ada", "Bob", "Bob"]` / `["2", "1", "3"]`
- Got: `["Bob", "Ada", "Bob"]` / `["1", "2", "3"]` (unsorted)

**`SyncQuerySortSugarTests.testGeneratedSortDescriptorsIgnoreUnsupportedKeyPaths`** — also affected (but currently shows pass; the ordering test fails first)

**`SyncContainerSchemaValidationTests.testSchemaValidationFailsForManyToManyPairWithoutExplicitInverseAnchor`**
- `SyncContainer(for:..., schemaValidation: .failFast)` does not throw
- Expected: `SchemaValidationError` with "many-to-many" in message
- Got: no error (validation skips because `syncRelationshipSchemaDescriptors` always returns `[]`)

### Attempted Fix — Caused Crashes (BLOCKED)

Promoting both methods to formal protocol requirements in `SyncModelable` body fixes the dispatch, but causes **SIGSEGV (signal 11) crashes** in the test process when any of the affected test suites run. The crash happens at test case start, before any test body executes.

The crash was not present before the protocol collapse (when these were requirements on the now-deleted separate protocols). The root cause of the crash under the new arrangement is not yet identified.

Exact crash scenario:
```
Test Case '-[IntegrationTests.SyncContainerSchemaValidationTests testSchemaValidationAllowsManyToManyPairWithOneExplicitInverseAnchor]' started.
error: Exited with unexpected signal code 11
```

### Next Steps to Investigate

1. Try promoting **only `syncRelationshipSchemaDescriptors`** as a formal requirement (not `syncSortDescriptor`) — see if just that one causes the crash
2. Try adding `syncSortDescriptors` (plural) as the formal requirement instead of `syncSortDescriptor` (singular), and generate it directly from the macro
3. Consider rewriting `SyncContainer._schemaRelationships` to use a concrete-type dispatch trick instead of existential, avoiding the need for the protocol requirement
4. Investigate the SIGSEGV more deeply (possibly a SwiftData keypath comparison issue when `@Model` properties are accessed during class loading)
