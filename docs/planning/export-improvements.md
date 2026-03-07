# Export System Improvements

## Goal

Make export behavior deterministic, documented, and regression-safe for library users and Demo paths.

## Why this work

- Export is a contract boundary. Silent shape changes become backend breakages.
- The current fallback for unsupported types (`NSNull`) is easy to miss without explicit tests and docs.
- `Data`, `Decimal`, and bare `@PrimaryKey` key mapping are valid export paths that should be pinned by tests.
- Export configuration APIs exist (`ExportOptions`, `KeyStyle`, `exportObject(for:container:)`) but are under-documented.

## Mental model

- Test behavior at the public API boundary first (`SwiftSync.export(...)`, `exportObject(...)`).
- Preserve current behavior unless a change is intentional and explicitly documented.
- Keep library flexibility (snake_case and camelCase support), but make defaults and derivation rules obvious.

## Current validated state

- `exportEncodeValue` supports a fixed set of scalar/collection types and returns `nil` for unsupported types.
- `@Syncable` export generation writes `NSNull()` when `exportEncodeValue` returns `nil`.
- Relationship export behavior is already covered for `SwiftSync.export(as:in:)`.
- `exportObject(for:container:)` tests currently verify key-style and date-formatter derivation.
- `Data` and `Decimal` are supported by `exportEncodeValue`, but no dedicated regression test currently pins those encode paths.
- `@PrimaryKey(remote: ...)` export mapping is covered; bare `@PrimaryKey` export-key mapping is not explicitly covered.

## Scope

- In scope: export encoding behavior, export key mapping behavior, and export API documentation.
- Out of scope: inbound sync parsing, backend request validation, and non-export relationship sync logic.

## Success criteria

- Export behavior for unsupported values, `Data`, `Decimal`, and bare `@PrimaryKey` is covered by regression tests.
- Public export configuration APIs have doc comments that explain defaults and container-derived behavior.
- Existing export wire shapes remain stable unless a behavior change is intentionally introduced.

## Open items

- [ ] Add a regression test that pins current unsupported-type export behavior (`NSNull` output).
- [ ] Add export regression tests for `Data` (base64 string) and `Decimal` (`NSDecimalNumber`) encoding.
- [ ] Add a regression test for bare `@PrimaryKey` export key mapping under default key style.
- [ ] Add doc comments for `ExportOptions`, `KeyStyle`, and `exportObject(for:container:)`.
