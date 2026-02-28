# Demo Coverage Gap — Complexity Reduction Candidates

**Purpose:** Map the delta between SwiftSync's current public API surface and what the demo
actually exercises. Every gap is a candidate for reduction — either remove, make internal, or
explicitly defer to an advanced tier. Work through Section 5 top-to-bottom, one checkbox at a time.

---

## 1. Baseline: what the demo actually uses

The demo is the reference implementation of the intended happy path. If it isn't needed here,
it needs a strong justification to stay public.

| API | Where used in demo |
|---|---|
| `@Syncable` | All 5 model classes |
| `@RemoteKey` | `Task.descriptionText`, `Task.state`, `Task.stateLabel`, `User.role`, `User.roleLabel` |
| `SyncContainer(for:recoverOnFailure:configurations:)` | `DemoRuntime` |
| `SyncContainer.modelContainer` | `DemoApp` (scene modifier) |
| `SyncContainer.mainContext` | `DemoSyncEngine` (direct fetch) |
| `syncContainer.sync(payload:as:)` | Projects, Users, TaskStateOptions, UserRoleOptions |
| `syncContainer.sync(payload:as:parent:)` | Tasks scoped to a Project |
| `syncContainer.sync(item:as:)` | Single-task detail re-sync (`syncTaskDetailInternal`) |
| `@SyncQuery(_:in:sortBy:[SortDescriptor])` | Users, TaskStateOptions, Projects |
| `@SyncQuery(_:relatedTo:relatedID:in:sortBy:refreshOn:animation:)` | Tasks for a Project |
| `@SyncModel(_:id:in:animation:)` | Project and Task lookup |
| `SyncQueryPublisher(_:in:sortBy:)` | `ProjectsViewController` (UIKit table) |
| `SyncContainer.SchemaValidationError` | thrown by `SyncContainer.init` on unanchored many-to-many |
| `SyncContainer.ObjectiveCInitializationExceptionError` | thrown by `SyncContainer.init` on NSException from ModelContainer |

Everything not in this table is unused by the demo.

---

## 2. Unused surface by subsystem

Ordered by estimated reduction impact (largest first).

---

### 2.1 Export system

The entire export subsystem — protocol requirement, options, state, free functions, and the
`@NotExport` macro — is absent from the demo. It is fully tested in `ExportTests.swift` but
represents a significant surface area that a first-time integrator never needs to touch.

Specific unused items:

- [ ] `ExportOptions` struct (all properties, static presets, `defaultDateFormatter()`)
- [ ] `ExportState` struct (`enter(_:)`, `leave(_:)`)
- [ ] `enum ExportRelationshipMode` (`.array`, `.nested`, `.none`)
- [ ] `enum ExportKeyStyle` (`.snakeCase`, `.camelCase`, `transform(_:)`)
- [ ] `exportEncodeValue(_:options:)` free function
- [ ] `exportSetValue(_:for:into:)` free function
- [ ] `SwiftSync.export(as:in:using:)` static method
- [ ] `SwiftSync.export(as:in:parent:using:)` static method
- [ ] `exportObject(using:state:)` protocol requirement on `SyncUpdatableModel`
- [ ] `@NotExport` macro

**Recommendation:** Extract to a separate `SwiftSyncExport` module or hide behind a build flag.
The implementation is complete and tested — this is about decoupling it from the core import
path, not discarding the work.

---

### 2.2 Low-level context API (`SwiftSync.sync` / `SwiftSync.export` on `ModelContext` directly)

These static methods let callers bypass `SyncContainer` entirely and drive sync against a raw
`ModelContext`. The demo never calls them — it always goes through `SyncContainer`.

- [ ] `SwiftSync.sync(payload:as:in:inputKeyStyle:relationshipOperations:)` — global
- [ ] `SwiftSync.sync(item:as:in:inputKeyStyle:relationshipOperations:)` — global single-item
- [ ] `SwiftSync.sync(payload:as:in:parent:inputKeyStyle:relationshipOperations:)` — ParentScopedModel
- [ ] `SwiftSync.sync(payload:as:in:parent:inputKeyStyle:relationshipOperations:)` — inferred parent
- [ ] `SwiftSync.sync(item:as:in:parent:inputKeyStyle:relationshipOperations:)` — inferred parent single-item
- [ ] `SwiftSync.export(as:in:using:)` — (also listed under 2.1; listed here for completeness)
- [ ] `SwiftSync.export(as:in:parent:using:)` — (same)

**Recommendation:** Make `internal`. `SyncContainer` is the intended public entry point. The raw
context overloads exist for internal plumbing and testing — they should not be on the public API.

---

### 2.3 Manual relationship helper free functions

These five functions are generated and called by `@Syncable`-expanded code. They are `public`
so the macro-expanded code can reference them, but they are not intended to be called by hand.
The demo never calls them directly.

- [ ] `syncApplyToOneForeignKey(_:relationship:payload:keys:in:operations:)` — optional `Related?` variant
- [ ] `syncApplyToOneForeignKey(_:relationship:payload:keys:in:operations:)` — non-optional `Related` variant
- [ ] `syncApplyToManyForeignKeys(_:relationship:payload:keys:in:operations:)`
- [ ] `syncApplyToOneNestedObject(_:relationship:payload:keys:in:operations:)`
- [ ] `syncApplyToManyNestedObjects(_:relationship:payload:keys:in:operations:)`

**Note:** The `PersistentModel`-constrained stub overloads (no-op returns) are only needed to
satisfy generic resolution — they could be `package` or `internal` if the macro and library
targets are merged.

**Recommendation:** Make `internal` (or `package`-scoped if macros expand into the same package).
Document that these are implementation details of `@Syncable`, not public primitives.

---

### 2.4 `SyncPayload` direct API

`SyncPayload` is constructed and consumed entirely inside the library. Users never create one
manually — the library creates it during sync from the raw `[Any]` payload. The demo never
references `SyncPayload` at all.

- [ ] `SyncPayload` struct itself (public visibility)
- [ ] `SyncPayload.strictValue(for:as:)` — non-coercive accessor
- [ ] `SyncPayload.required(_:for:)throws` — throwing required accessor
- [ ] `SyncPayload.strictRequired(_:for:)throws` — strict throwing required accessor

**Note:** `SyncPayload` appears in the `SyncUpdatableModel` protocol requirements (`make(from:)`,
`apply(_:)`), so its type must be visible to conforming code. The struct itself may need to stay
public, but the additional accessor variants can likely be internal.

**Recommendation:** Keep `SyncPayload` and `value(for:)` public (required by protocol surface).
Make `strictValue`, `required`, `strictRequired` internal — they are library-internal resolution
strategies, not user-facing accessors.

---

### 2.5 `SyncDateParser`, `DateType`, `String.dateType()`

These are purely internal date-parsing utilities. They are `public` but never referenced outside
the library. The demo never imports or calls them.

- [ ] `enum SyncDateParser` — all four static methods
- [ ] `enum DateType` (`.iso8601`, `.unixTimestamp`)
- [ ] `String.dateType()` extension method

**Recommendation:** Make `internal`. No user-facing use case exists. These are implementation
details of `apply(_:)` and `make(from:)` codegen.

---

### 2.6 `SwiftSync.inferToOneRelationship` / `inferToManyRelationship`

These static methods infer relationship key paths from a model type. They are called internally
during parent-scoped sync to resolve the correct key path. They are `public` but have no
user-facing use case — the inference happens transparently when calling `sync(payload:as:parent:)`.

- [ ] `SwiftSync.inferToOneRelationship(for:parent:)throws`
- [ ] `SwiftSync.inferToManyRelationship(for:related:)throws`

**Recommendation:** Make `internal`. Callers never need to invoke inference explicitly.

---

### 2.7 `SyncContainer` notification constants

These three static strings are used internally by `SyncQuery` and `SyncQueryPublisher` to
coordinate reload decisions after a save. They are `public` but the demo never references them.

~~`SyncContainer.didSaveChangesNotification`~~ — made `internal`
~~`SyncContainer.changedIdentifiersUserInfoKey`~~ — made `internal`
~~`SyncContainer.changedModelTypeNamesUserInfoKey`~~ — made `internal`

---

### 2.8 `SyncRelationshipOperations` granularity

The demo passes the default `.all` everywhere (by not passing `relationshipOperations:` at all).
The individual bit values (`.insert`, `.update`, `.delete`) are tested in
`RelationshipOperationsTests.swift` but represent a level of control no common use case requires.

- [ ] `SyncRelationshipOperations.insert` (bit value)
- [ ] `SyncRelationshipOperations.update` (bit value)
- [ ] `SyncRelationshipOperations.delete` (bit value)
- [ ] The `relationshipOperations:` parameter on all public `sync` overloads

**Recommendation:** Evaluate replacing the OptionSet with a simpler `Bool` (`applyRelationships:`)
or removing the parameter entirely and always applying all operations. The OptionSet adds four
public symbols and non-trivial mental overhead for a feature no demo path exercises.

---

### 2.9 `SyncQueryPublisher` unused init variants

The demo uses only the plain `SyncQueryPublisher(_:in:sortBy:)` init (in `ProjectsViewController`).
The predicate and `relatedTo:through:` inits are untouched.

- [ ] `SyncQueryPublisher(_:predicate:in:sortBy:)`
- [ ] `SyncQueryPublisher(_:relatedTo:relatedID:through:in:sortBy:)` — to-one explicit
- [ ] `SyncQueryPublisher(_:relatedTo:relatedID:through:in:sortBy:)` — to-many explicit

**Note:** `SyncQueryPublisher` is itself an underdiscovered class. If `@SyncQuery` covers SwiftUI
and `SyncQueryPublisher` covers UIKit, the publisher's API surface should mirror the query's.
But if the UIKit story is being narrowed, consider whether three extra inits are justified.

**Recommendation:** Evaluate removing the predicate and `relatedTo:through:` inits from
`SyncQueryPublisher`, or unshipping the class until the UIKit story is more developed.

---

### 2.10 `SyncContainer(modelContainer:inputKeyStyle:)` alternate init

This init wraps an existing `ModelContainer` (e.g. one created by app startup code) instead of
constructing one from model types. It's an escape hatch for advanced integration. The demo uses
the variadic-model init exclusively.

- [ ] `SyncContainer.init(_:ModelContainer, inputKeyStyle:)`

**Recommendation:** Keep — the escape hatch is low-cost and legitimately useful. But consider
whether it needs to be in the primary docs or can be left as a discoverable secondary entry point.

---

### 2.11 `TestingKit` target and `SwiftSyncFixtures`

`TestingKit` is a separate library target that exports `SwiftSyncFixtures` — two canned payloads
(`usersPayload`, `emptyPayload`). It is not imported by the demo and not referenced in the
integration tests (which build their own inline fixtures).

- [ ] `TestingKit` target itself
- [ ] `SwiftSyncFixtures.usersPayload`
- [ ] `SwiftSyncFixtures.emptyPayload`

**Recommendation:** Evaluate removing the target. If fixture sharing is needed across test
targets, the fixtures can live directly in the test helpers. A public `TestingKit` product
signals an intentional testing SDK — which may not be a commitment worth making yet.

---

### 2.12 `@PrimaryKey`, `@RemotePath`, `@NotExport` macros

These macros are not used in demo models but are tested and represent real use cases:

- `@PrimaryKey` — models whose identity field isn't named `id` / `remoteID`
- `@RemotePath` — deep path imports (e.g. `"state.id"` nested in JSON), also used indirectly in
  demo via `@RemoteKey("state.id")` (which is a flat-key variant, not a path variant)
- `@NotExport` — opt-out from export serialization

- [ ] Review whether `@RemotePath` is the right boundary vs `@RemoteKey` with dot notation
      (demo uses `@RemoteKey("state.id")` which already traverses a dot path)
- [ ] Confirm `@PrimaryKey` and `@NotExport` are intentionally public-and-documented as advanced features

**Recommendation:** Keep all three. They are intentional advanced features. Ensure they are
clearly marked as advanced in docs rather than being hidden or removed.

---

## 3. Summary reduction table

| Subsystem | Approx. symbols | Demo usage | Action |
|---|---|---|---|
| Export system | ~10 | None | Extract to separate module |
| Low-level context API | 5 overloads | None | Make `internal` |
| Manual relationship helpers | 5 free functions | None (macro-generated) | Make `internal` or `package` |
| `SyncPayload` accessors | 3 methods | None | Make `internal` |
| `SyncDateParser` / `DateType` | 6 | None | Make `internal` |
| Inference functions | 2 | None (internal) | Make `internal` |
| Notification constants | 3 statics | None (internal) | ✅ Made `internal` |
| `SyncRelationshipOperations` bits | 4 | `.all` default only | Evaluate simplification |
| `SyncQueryPublisher` extra inits | 3 | None | Evaluate removal |
| `SyncContainer` alternate init | 1 | None | Keep |
| `TestingKit` target | 1 target, 2 symbols | None | Evaluate removal |
| `@PrimaryKey`, `@RemotePath`, `@NotExport` | 3 macros | None in demo | Keep, mark as advanced |

---

## 4. `SyncModelable` protocol extension surface

Several extension methods on `SyncModelable` are also not called directly by the demo. They are
generated by `@Syncable` or used internally by `SyncQuery`. Mark as internal noise rather than
removal candidates (they power the reactive layer), but they should be audited for public necessity:

- [ ] `syncDefaultRefreshModelTypeNames` (computed var)
- [ ] `syncRefreshModelTypes(for:)` static func
- [ ] `syncRefreshModelTypeNames(for:)` static func
- [ ] `syncRelatedModelType(for:)` static func
- [ ] `syncRelationshipSchemaDescriptors` static var
- [ ] `SyncRelationshipSchemaDescriptor` struct
- [ ] `SyncRelationshipSchemaIntrospectable` protocol (separate from `SyncModelable`)

**Recommendation:** These are internal coordination APIs between the macro output and the query
layer. Evaluate making them `internal` if the macro expansion and query targets can be merged or
if `@testable import` covers test access needs.

---

## 5. Execution checklist

Work through these in order. Each item is a discrete, independently executable task. Run tests
after each item before proceeding.

**Safest / purely visibility changes (no behavior risk):**

- [ ] 1. Make `SyncDateParser`, `DateType`, and `String.dateType()` `internal`
- [ ] 2. Make `SwiftSync.inferToOneRelationship` and `inferToManyRelationship` `internal`
- [x] 3. Made `SyncContainer.didSaveChangesNotification`, `changedIdentifiersUserInfoKey`, `changedModelTypeNamesUserInfoKey` `internal`
- [ ] 4. Make `SyncPayload.strictValue`, `SyncPayload.required`, `SyncPayload.strictRequired` `internal`
- [ ] 5. Make `syncApplyToOneForeignKey`, `syncApplyToManyForeignKeys`, `syncApplyToOneNestedObject`, `syncApplyToManyNestedObjects` `internal` (or `package`)

**Evaluate and decide (may affect external callers):**

- [ ] 6. Remove `SwiftSync.sync(payload:as:in:…)` public static overloads — make `internal` and route all public entry points through `SyncContainer`
- [ ] 7. Remove or reduce `SyncQueryPublisher` init variants not used by the demo (predicate, `relatedTo:through:`)
- [ ] 8. Evaluate removing `TestingKit` target — absorb fixtures into test helpers or delete
- [ ] 9. Evaluate `SyncRelationshipOperations` simplification — replace OptionSet with a plain `Bool` or remove the parameter and always apply `.all`
- [x] 10. ~~Evaluate `SyncMissingRowPolicy.keep`~~ — removed; replaced by `sync(item:)` targeted upsert overload

**Structural (highest effort, highest payoff):**

- [ ] 11. Extract the export subsystem (`ExportOptions`, `ExportState`, `ExportRelationshipMode`, `ExportKeyStyle`, `exportEncodeValue`, `exportSetValue`, `export()` overloads, `exportObject` protocol requirement, `@NotExport`) into a separate `SwiftSyncExport` module or guard behind a compiler flag — do not ship as part of the core `SwiftSync` import
- [ ] 12. Audit `SyncModelable` protocol extension methods for `internal` candidacy once the macro and query targets' module boundaries are settled
