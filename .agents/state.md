# State Capsule

## Plan
- [x] Remove `ExportRelationshipMode.nested` case from `Core.swift`
- [x] Remove `.nested` branches from `exportBlock(for:)` in `SyncableMacro.swift`
- [x] Remove `.nested` assertions from `SyncExportTests.swift`
- [x] Update `ARCHITECTURE.md`, `README.md`, planning docs for `.nested` removal
- [x] Run `swift test` — confirm green (pass 1)
- [x] Add `docs/planning/export-options-evaluation.md` — decision to keep `ExportOptions`
- [x] Remove `ExportRelationshipMode` enum entirely from `Core.swift`
- [x] Remove `relationshipMode` field from `ExportOptions` and its init
- [x] Remove `ExportOptions.excludedRelationships` static
- [x] Remove `relationshipMode:` parameter from `exportObject(for:container:)`
- [x] Remove `if options.relationshipMode == .array` guards from `SyncableMacro.swift`; wrap relationship export blocks in `do { }` for scoping
- [x] Remove `ExportOptions(relationshipMode: .none)` and `exportObject(for:syncContainer:relationshipMode:.none)` from `SyncExportTests.swift`
- [x] Remove `relationshipMode: .none` from `TaskFormSheet.swift`
- [x] Update `ARCHITECTURE.md`, `README.md`, planning docs for full removal
- [x] Run `swift test` — confirm green (pass 2)

## Last known state
112 + 30 tests green (2026-03-04)

## Decisions (don't revisit)
- `.nested` removed — speculative, Rails-specific, no concrete consumer.
- `ExportRelationshipMode` removed entirely — with only `.array` and `.none` remaining, the concept was a boolean in disguise. `@NotExport` is the declarative exclusion mechanism; no runtime toggle needed.
- `ExportOptions` kept — struct is now minimal (keyStyle + dateFormatter) but the internal protocol contract (`exportObject(using:)`) and the `.camelCase` static justify it. Removal cost exceeds benefit.
- Macro relationship export blocks wrapped in `do { }` to scope `baseKey`/`exportedChildren`/`anyChild` — required after removing the `if { }` guard that previously scoped them.

## Files touched
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- Demo/Demo/Features/TaskFormSheet.swift
- ARCHITECTURE.md
- README.md
- docs/planning/export-improvements.md
- docs/planning/export-nested-mode.md
- docs/planning/demo-coverage-gap.md
- docs/planning/checklist-items-array-export.md
- docs/planning/export-options-evaluation.md
