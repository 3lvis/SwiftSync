# Export System Improvements

## Goal

Make export behavior deterministic and regression-safe for library users and Demo paths.

## Why this work

- Export is a contract boundary. Silent shape changes become backend breakages.
- The current fallback for unsupported types (`NSNull`) is easy to miss without explicit tests.
- `Data`, `Decimal`, and bare `@PrimaryKey` key mapping are valid export paths that should be pinned by tests.

## Current validated state

- `exportEncodeValue` supports a fixed set of scalar/collection types and returns `nil` for unsupported types.
- `@Syncable` export generation writes `NSNull()` when `exportEncodeValue` returns `nil`.
- Relationship export behavior is already covered for `SwiftSync.export(as:in:)`.
- `exportObject(for:container:)` tests currently verify key-style and date-formatter derivation.

## Scope

- In scope: export encoding behavior and export key mapping behavior.
- Out of scope: inbound sync parsing, backend request validation, and non-export relationship sync logic.

## Open items

- [ ] Add an explicit regression test for unsupported scalar type -> `NSNull` fallback.
- [ ] Add a dedicated export test with a model containing `Data` and `Decimal` fields.
- [ ] Add an explicit export test for bare `@PrimaryKey` key naming (only `@PrimaryKey(remote:)` is explicitly tested).
