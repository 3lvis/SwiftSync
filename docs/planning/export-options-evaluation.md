# ExportOptions Evaluation

## Context

After removing `ExportRelationshipMode.nested` and then `ExportRelationshipMode` entirely
(replacing it with `@NotExport` as the declarative exclusion mechanism), `ExportOptions`
is left with two fields:

```swift
public struct ExportOptions: Sendable {
    public var keyStyle: KeyStyle          // .snakeCase | .camelCase
    public var dateFormatter: DateFormatter
}
```

The question: is `ExportOptions` still pulling its weight as a named struct, or should
its remaining fields be dissolved into the `exportObject` / `SwiftSync.export` call sites
directly?

---

## What ExportOptions currently does

### `keyStyle: KeyStyle`

Controls whether property names are transformed to `snake_case` (default) or left as
`camelCase`. Used in:

- `SwiftSync.export(as:in:using:)` bulk export
- `exportObject(using:)` on the protocol
- `SyncContainer` picks up the container's `keyStyle` and passes it through
  `exportObject(for:container:)` convenience

Real usage in tests and demo:
- `ExportOptions.camelCase` static — used in `testExportCamelCaseKeys`
- `SyncContainer(modelContainer, keyStyle: .camelCase)` — used in several sync tests
  (for inbound key mapping, not export)
- `exportObject(for: syncContainer)` inherits the container's `keyStyle` automatically

### `dateFormatter: DateFormatter`

Controls ISO8601 output format for `Date` fields. The default formats to
`yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX`. Overridable for apps with a non-standard date format.

Real usage:
- `ExportOptions.defaultDateFormatter()` — used in `SyncContainer` init and `ExportOptions` init
- `testExportCustomDateFormatter` — sets a custom formatter on `ExportOptions` directly
- `testExportForContainerDerivesDateFormatterFromContainer` — verifies the container's
  formatter flows through `exportObject(for:container:)`

---

## Should ExportOptions be removed?

### The case for keeping it

1. **It groups two orthogonal concerns that callers often want to set together.**
   A camelCase API backend needs both `keyStyle: .camelCase` and possibly a custom date
   format. Passing them together as one `ExportOptions` value is ergonomic.

2. **It is already minimal.** Two fields. There is nothing bloated about it now.

3. **`SwiftSync.export(as:in:using:)` passes `ExportOptions` through the bulk path.**
   Replacing it would mean either adding two separate parameters to every export function
   or losing the ability to configure them at all in the bulk path.

4. **The `exportObject(using: ExportOptions)` protocol requirement is the internal
   contract between the library and `@Syncable`-generated code.** The macro generates
   `func exportObject(using options: ExportOptions)`. Removing `ExportOptions` means
   changing the protocol, regenerating all macro output, and changing the internal
   call contract — significant churn for no user-facing benefit.

5. **`ExportOptions.camelCase` is a useful named shorthand.** `SwiftSync.export(as: X.self, in: ctx, using: .camelCase)` reads cleanly and is the primary call pattern in tests.

### The case for removing it

1. **Only two fields remain.** `SwiftSync.export` could take `keyStyle:` and
   `dateFormatter:` as separate parameters with defaults.
2. **The `ExportOptions` type leaks into every `exportObject(using:)` protocol
   conformance**, which is an implementation detail most callers never see.

### Verdict: keep ExportOptions

The removal cost (protocol change, macro regeneration, every `exportObject(using:)`
conformance) is not justified by the gain. The struct is already minimal and the
internal protocol contract makes it the right abstraction boundary between the library
and macro-generated code.

The `excludedRelationships` static is the only thing that was removed when
`ExportRelationshipMode` was eliminated. The remaining two statics (`.camelCase` and
the implicit default) are both genuinely useful.

---

## Follow-on: `ExportOptions` doc comments

`ExportOptions`, `KeyStyle`, and `exportObject(for:container:)` have no doc comments.
Now that the struct is stable, add doc comments explaining:

- `ExportOptions` — what it controls, when to use a custom instance vs. the defaults
- `KeyStyle` — what `.snakeCase` and `.camelCase` produce, with examples
- `exportObject(for:container:)` — that it inherits `keyStyle` and `dateFormatter`
  from the container; relationships are included unless `@NotExport` is applied

This is tracked in `docs/planning/export-improvements.md` (item 4, now updated to
reflect the removal of the relationship-mode asymmetry note).

---

## Status

Evaluated (2026-03-04). No structural changes to `ExportOptions` planned.
Doc comments deferred to a future pass (tracked in `export-improvements.md`).
