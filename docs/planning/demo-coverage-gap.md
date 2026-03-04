# Demo Coverage Gap — Complexity Reduction Candidates

**Superseded by:** `api-surface-reduction.md` for active work queue.  
**Purpose:** Reference for open reduction candidates not yet scheduled.

---

## Unused surface — open candidates

### Export system (bulk paths)

The core `exportObject` path is exercised by the demo. These remain uncovered:

- [ ] `enum ExportRelationshipMode` — `.array` variant (`.nested` removed)
- [ ] `exportEncodeValue(_:options:)` free function
- [ ] `exportSetValue(_:for:into:)` free function
- [ ] `SwiftSync.export(as:in:using:)` static method (bulk export)
- [ ] `SwiftSync.export(as:in:parent:using:)` static method
- [ ] `@NotExport` macro

**Note:** Bulk export entry point and mode variants are uncovered. Consider a round-trip export demo scenario (e.g. export tasks to a share sheet) before extracting to a separate module.

---

### Manual relationship helper free functions

Generated and called by `@Syncable`-expanded code. `public` because macro expansion happens in client module scope. Not intended to be called by hand.

- [ ] `syncApplyToOneForeignKey` (all overloads)
- [ ] `syncApplyToManyForeignKeys`
- [ ] `syncApplyToOneNestedObject`
- [ ] `syncApplyToManyNestedObjects`

**Blocked by:** `package` access level — cannot make internal without an SPM solution. Deferred.

---

### `SyncRelationshipOperations` granularity

Demo passes `.all` everywhere. Individual bit values are tested but represent a level of control no common use case requires.

- [ ] Evaluate replacing the OptionSet with a simpler `Bool` (`applyRelationships:`) or removing the parameter entirely
- [ ] Decided: keep as-is for now (see `api-surface-reduction.md` decisions)

---

### `SyncQueryPublisher` unused init variants

**Scheduled in `api-surface-reduction.md` item 1.**

---

### `TestingKit` target

`TestingKit` exports `SwiftSyncFixtures` (`usersPayload`, `emptyPayload`). Not imported by the demo. Not referenced in integration tests.

- [ ] Evaluate removing — absorb fixtures into test helpers or delete the target

---

### `@PrimaryKey`, `@RemotePath`, `@NotExport` macros

Not used in demo models. Intentional advanced features — keep, but ensure clearly marked as advanced in docs.

- [ ] Review whether `@RemotePath` is the right boundary vs `@RemoteKey` with dot notation
- [ ] Confirm `@PrimaryKey` and `@NotExport` are documented as advanced features

---

### `SyncModelable` protocol extension surface

Internal coordination APIs between macro output and query layer. Not called directly by the demo.

- [ ] Audit for `internal` candidacy: `syncDefaultRefreshModelTypeNames`, `syncRefreshModelTypes(for:)`, `syncRefreshModelTypeNames(for:)`, `syncRelatedModelType(for:)`, `syncRelationshipSchemaDescriptors`, `SyncRelationshipSchemaDescriptor`, `SyncRelationshipSchemaIntrospectable`

**Deferred** — needs module boundary analysis first.
