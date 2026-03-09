# Nested To-Many Dirty Tracking Coverage Gap

## Why

SwiftSync documents an iOS dirty-tracking workaround for to-many membership changes and has focused test coverage proving that workaround for foreign-key driven to-many sync.

That is not the same as proving the same guarantee for every to-many mutation path in the library.

Today the contract appears stronger in prose than in code:

- `syncApplyToManyForeignKeys` calls `owner.syncMarkChanged()` when membership changes.
- `syncApplyToManyNestedObjects` does not currently make the same call.
- Existing tests explicitly describe coverage for the foreign-key path, not the nested-object path.

This matters because the user-facing expectation is not “some to-many updates notify correctly.” If SwiftSync intends to guarantee reliable owner updates after synced to-many membership changes that would otherwise fall into the SwiftData/Core Data dirty-tracking gap on iOS, that guarantee is currently proven for the foreign-key path but not clearly for the nested-object path.

Without tighter coverage and a narrowed statement of scope, the project risks three kinds of confusion:

- Documentation drift: the docs imply a broader fix than the tests currently prove.
- Behavioral drift: one path can regress while the other remains green.
- Adoption risk: library users may assume nested relationship payloads are covered by the same notification guarantees as `*_ids` payloads.

## What

This work should define and document the exact contract for dirty-tracking compensation across to-many sync paths.

The intended output is clarity, not implementation detail:

## Open items

- [ ] State the supported guarantee in library docs using path-specific language.
- [ ] Identify every to-many mutation path in SwiftSync and classify whether it is expected to trigger `syncMarkChanged()`.
- [ ] Record the current gap between foreign-key to-many handling and nested-object to-many handling.
- [ ] Specify the minimum test matrix needed to prove parity or intentionally document non-parity.
- [ ] Decide whether nested-object to-many updates are part of the same public notification contract as foreign-key to-many updates.
- [ ] Define the acceptance criteria for closing this planning item without prescribing code changes yet.

## References

- `SwiftSync/Sources/SwiftSync/Core.swift`
- `SwiftSync/Tests/SwiftSyncTests/SyncRelationshipIntegrityTests.swift`
- `docs/project/ios-dirty-tracking-gap.md`
