# Export System Improvements

---

## Open items

- [ ] Add a guardrail for unsupported export property types (`exportEncodeValue` fallthrough to `NSNull`).
- [ ] Add a macro diagnostic for `@RemotePath` used on relationship properties.
- [ ] Document export-mode asymmetry (`.none` omits relationship keys; nil scalars emit `NSNull`).
- [ ] Fill export test coverage gaps (convenience mode coverage, `Data`/`Decimal`, bare `@PrimaryKey`, empty to-many `.nested`).

---

## 1) Unsupported export property types currently become silent `NSNull`

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

## 2) `@RemotePath` on a relationship property produces a broken key in `.nested` mode

If someone writes `@RemotePath("foo.bar") var child: RelatedModel?`, the export in
`.nested` mode calls `exportSetValue(child, for: "foo.bar_attributes", into: &result)`.
`exportSetValue` splits on `.` — so it writes into `result["foo"]["bar_attributes"]`
instead of the presumably intended `result["foo.bar_attributes"]`. Almost certainly
unintended, and untested.

**Fix:** Guard in the macro: emit a diagnostic error if `@RemotePath` is applied to a
relationship property. `@RemotePath` is only valid for scalar fields.

---

## 3) Undocumented asymmetry: `.none` mode omits keys vs. scalar nil emits `NSNull`

`ExportOptions`, `KeyStyle`, and `exportObject(for:container:)` have no doc comments.
Add doc comments explaining:

- `ExportOptions` — what it controls, when to use a custom instance vs. the defaults
- `KeyStyle` — what `.snakeCase` and `.camelCase` produce, with examples
- `exportObject(for:container:)` — that it inherits `keyStyle` and `dateFormatter` from
  the container; relationships are included unless `@NotExport` is applied to the property

---

## 4) Missing test coverage

### 4a) `exportObject(for:container:)` with `.array` and `.nested`

The instance convenience `exportObject(for:container:)` is tested only for scalar
key/date derivation from the container. Add a test that verifies relationship properties
are included in the output when not marked `@NotExport`.

### 4b) `Data` and `Decimal` encode paths in `exportEncodeValue`

`Core.swift` handles `Data` (→ base64 string) and `Decimal` (→ `NSDecimalNumber`).
Neither type appears in any test model. Add a model with `Data` and `Decimal` fields
and assert the encoded values.

### 4c) Bare `@PrimaryKey` export key

`@PrimaryKey` with no `remote:` argument falls through to `keyStyle.transform(propertyName)`
for the export key. `@PrimaryKey(remote: "ext_id")` uses the literal. Only the latter is
tested. Add a test for the bare `@PrimaryKey` case.
### 4d) Empty to-many in `.nested` mode

An empty `[Model]` in `.nested` mode currently produces `"tags_attributes": {}` (empty
dict). Add a test that pins this behaviour and documents whether `{}` or omission is
intended.
