# State Capsule

## Plan
- [x] Remove `ExportRelationshipMode.nested` case from `Core.swift`
- [x] Remove `.nested` branches from `exportBlock(for:)` in `SyncableMacro.swift`
- [x] Remove `.nested` assertions from `testExportRelationshipModesArrayNestedNone` in `SyncExportTests.swift` (test renamed to `testExportRelationshipModesArrayNone`)
- [x] Update `ARCHITECTURE.md` — remove `.nested` row from ExportRelationshipMode table and "Things Worth Reducing" entry
- [x] Update `README.md` — remove "Nested relationship export" section
- [x] Update `docs/planning/export-improvements.md` — remove 5d (empty to-many in .nested), update 5a
- [x] Update `docs/planning/demo-coverage-gap.md` — note .nested removed
- [x] Update `docs/planning/export-nested-mode.md` — replace recommendation with resolution
- [x] Run `swift test` — confirm green

## Last known state
112 + 30 tests green (2026-03-04)

## Decisions (don't revisit)
- `.nested` removed because it was speculative (no concrete consumer), Rails-specific format, and SwiftSync is not exclusively targeting Rails backends. `.array` covers inline child export for all REST backends.
- Macro `exportBlock` for relationships simplified from switch-on-mode to a simple `if options.relationshipMode == .array` guard — no switch needed with only two cases.

## Files touched
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- ARCHITECTURE.md
- README.md
- docs/planning/export-improvements.md
- docs/planning/demo-coverage-gap.md
- docs/planning/export-nested-mode.md
