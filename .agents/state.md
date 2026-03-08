# State Capsule

## Plan
- [x] Add failing tests for removing `ExportOptions` from export APIs.
- [x] Replace `ExportOptions` with direct `keyStyle` + `dateFormatter` export parameters in core protocols and macro output.
- [x] Update `SyncContainer` export implementation and defaults to no longer construct `ExportOptions`.
- [x] Remove stale docs/references that still mention `ExportOptions` as runtime API.
- [x] Run targeted and full `swift test`.
- [x] Remove historical planning docs for deprecated export APIs.
- [x] Align architecture/property-mapping docs with container-owned export and `keyStyle` naming.

## Last known state
`swift test --filter ExportTests` and full `swift test` are green after removing `ExportOptions`.

## Decisions (don't revisit)
- Standardize export configuration on `SyncContainer`; no backward compatibility for per-call export options in public API.
- Remove `ExportOptions` entirely; export configuration is expressed as `keyStyle` + `dateFormatter` parameters internally and by container defaults.
- Do not keep historical planning docs for removed export modes/options.

## Files touched
- .agents/state.md
- SwiftSync/Tests/SwiftSyncTests/SyncExportTests.swift
- SwiftSync/Sources/SwiftSync/SyncContainer.swift
- SwiftSync/Sources/SwiftSync/API.swift
- README.md
- docs/planning/demo-coverage-gap.md
- SwiftSync/Sources/SwiftSync/Core.swift
- SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift
- docs/project/property-mapping-contract.md
- ARCHITECTURE.md
- docs/planning/export-options-evaluation.md
- docs/planning/export-nested-mode.md
