# Export System Improvements

---

## 1. Fix stale docs — `ExportModel` and `includeNulls` references

`ExportModel` was folded into `SyncUpdatableModel`. `includeNulls` was removed.
Both still appear in `ARCHITECTURE.md` and `README.md`. Callers reading the docs
will get compile errors trying to use either.

**Files to fix:**
- `ARCHITECTURE.md:48,52,134` — remove `ExportModel` from protocol hierarchy diagram
  and macro output description
- `ARCHITECTURE.md:324` — remove `includeNulls` from optional scalar description
- `README.md:551` — remove `ExportModel` conformance from feature list
- `README.md:743,749` — update `export<Model: ExportModel>` signatures to
  `export<Model: SyncUpdatableModel>`

---

## 2. Silent NSNull for unrecognised property types

`exportEncodeValue` in `Core.swift` handles a fixed set of types (String, Int, Double,
Bool, Date, URL, Data, Decimal, UUID). If a model has a property of any other type —
a custom enum, a struct, a typealias over an unsupported type — `exportEncodeValue`
returns `nil` and the macro-generated code silently emits `NSNull()` for that field.

No warning, no compile error. The field appears in the export body as null rather than
being absent or causing a diagnostic.

**Fix options (pick one):**
- A. Add a doc comment to `exportEncodeValue` in `Core.swift` listing the supported
  types explicitly, so callers know what to expect.
- B. Emit a macro diagnostic warning when `@Syncable` encounters a property type it
  cannot statically verify is handled by `exportEncodeValue`.

The macro diagnostic (B) is the correct long-term fix. The doc comment (A) is a
lower-effort mitigation now.

---

## 3. `@RemotePath` on a relationship property produces a broken key in `.nested` mode

If someone writes `@RemotePath("foo.bar") var child: RelatedModel?`, the export in
`.nested` mode calls `exportSetValue(child, for: "foo.bar_attributes", into: &result)`.
`exportSetValue` splits on `.` — so it writes into `result["foo"]["bar_attributes"]`
instead of the presumably intended `result["foo.bar_attributes"]`. Almost certainly
unintended, and untested.

**Fix:** Guard in the macro: emit a diagnostic error if `@RemotePath` is applied to a
relationship property. `@RemotePath` is only valid for scalar fields.

---

## 4. Undocumented asymmetry: `.none` mode omits keys vs. scalar nil emits `NSNull`

`exportObject(for:container:)` defaults `relationshipMode` to `.none`, which omits
relationship keys entirely. `ExportOptions()` defaults `relationshipMode` to `.array`,
which includes relationship keys. Neither call site has a doc comment explaining this.

Separately: nil scalars always emit `NSNull` (PATCH semantics — explicit null clears the
field). Relationship keys under `.none` are simply absent. This asymmetry is intentional
but undocumented.

**Fix:** Add doc comments to:
- `exportObject(for:container:relationshipMode:)` in `Core.swift` explaining that `.none`
  omits relationship keys entirely and is the default for this convenience
- `ExportRelationshipMode.none` case explaining the omission-vs-null distinction

---

## 5. Missing test coverage

### 5a. `exportObject(for:container:)` with `.array` and `.nested`

The instance convenience `exportObject(for:container:relationshipMode:)` is only tested
with `relationshipMode: .none`. The `.array` and `.nested` modes are tested via the bulk
`SwiftSync.export()` path, not the instance convenience. Add tests that call the
convenience directly with all three modes.

### 5b. `Data` and `Decimal` encode paths in `exportEncodeValue`

`Core.swift` handles `Data` (→ base64 string) and `Decimal` (→ `NSDecimalNumber`).
Neither type appears in any test model. Add a model with `Data` and `Decimal` fields
and assert the encoded values.

### 5c. Bare `@PrimaryKey` export key

`@PrimaryKey` with no `remote:` argument falls through to `keyStyle.transform(propertyName)`
for the export key. `@PrimaryKey(remote: "ext_id")` uses the literal. Only the latter is
tested. Add a test for the bare `@PrimaryKey` case.

### 5d. Empty to-many in `.nested` mode

An empty `[Model]` in `.nested` mode currently produces `"tags_attributes": {}` (empty
dict). Add a test that pins this behaviour and documents whether `{}` or omission is
intended.
