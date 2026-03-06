# Export System Improvements

---

## Open items

- [ ] Add a guardrail for unsupported export property types (`exportEncodeValue` fallthrough to `NSNull`).
- [ ] Add doc comments for export configuration APIs (`ExportOptions`, `KeyStyle`, `exportObject(for:container:)`).
- [ ] Fill export test coverage gaps (convenience relationship coverage, `Data`/`Decimal`, bare `@PrimaryKey`).

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

## 2) Undocumented behavior: export configuration APIs

`ExportOptions`, `KeyStyle`, and `exportObject(for:container:)` have no doc comments.
Add doc comments explaining:

- `ExportOptions` — what it controls, when to use a custom instance vs. the defaults
- `KeyStyle` — what `.snakeCase` and `.camelCase` produce, with examples
- `exportObject(for:container:)` — that it inherits `keyStyle` and `dateFormatter` from
  the container; relationships are included unless `@NotExport` is applied to the property

---

## 3) Missing test coverage

### 3a) `exportObject(for:container:)` relationship coverage

The instance convenience `exportObject(for:container:)` is tested only for scalar
key/date derivation from the container. Add a test that verifies relationship properties
are included in the output when not marked `@NotExport`.

### 3b) `Data` and `Decimal` encode paths in `exportEncodeValue`

`Core.swift` handles `Data` (→ base64 string) and `Decimal` (→ `NSDecimalNumber`).
Neither type appears in any test model. Add a model with `Data` and `Decimal` fields
and assert the encoded values.

### 3c) Bare `@PrimaryKey` export key

`@PrimaryKey` with no `remote:` argument falls through to `keyStyle.transform(propertyName)`
for the export key. `@PrimaryKey(remote: "ext_id")` uses the literal. Only the latter is
tested. Add a test for the bare `@PrimaryKey` case.
