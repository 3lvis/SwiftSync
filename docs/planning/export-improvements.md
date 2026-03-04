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

## 4. Undocumented behaviour: `exportObject` and `ExportOptions`

`ExportOptions`, `KeyStyle`, and `exportObject(for:container:)` have no doc comments.
Add doc comments explaining:

- `ExportOptions` — what it controls, when to use a custom instance vs. the defaults
- `KeyStyle` — what `.snakeCase` and `.camelCase` produce, with examples
- `exportObject(for:container:)` — that it inherits `keyStyle` and `dateFormatter` from
  the container; relationships are included unless `@NotExport` is applied to the property

---

## 5. Missing test coverage

### 5a. `exportObject(for:container:)` — relationships included by default

The instance convenience `exportObject(for:container:)` is tested only for scalar
key/date derivation from the container. Add a test that verifies relationship properties
are included in the output when not marked `@NotExport`.

### 5b. `Data` and `Decimal` encode paths in `exportEncodeValue`

`Core.swift` handles `Data` (→ base64 string) and `Decimal` (→ `NSDecimalNumber`).
Neither type appears in any test model. Add a model with `Data` and `Decimal` fields
and assert the encoded values.

### 5c. Bare `@PrimaryKey` export key

`@PrimaryKey` with no `remote:` argument falls through to `keyStyle.transform(propertyName)`
for the export key. `@PrimaryKey(remote: "ext_id")` uses the literal. Only the latter is
tested. Add a test for the bare `@PrimaryKey` case.
