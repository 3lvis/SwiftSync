# State Capsule

## Plan
- [x] Create remove-include-nulls branch from export-simplification
- [x] Write updated tests first (rename old includeNulls tests, add Scenario A test)
- [x] Remove includeNulls from ExportOptions struct and init
- [x] Remove includeNulls: parameter from exportObject(for:container:) overload
- [x] Update macro exportBlock: replace all options.includeNulls branches with unconditional NSNull emission
- [x] Update demo call sites (TaskDetailView x3, ProjectsTabView x1)
- [x] Run full suite (156 tests green) and Demo BUILD SUCCEEDED
- [x] Commit

## Last known state
156/156 tests green / Demo BUILD SUCCEEDED

## Decisions (don't revisit)
- includeNulls removed entirely — nil optionals always emit NSNull; callers who want to "no-op" a field use @NotExport
- Scenario A (PATCH explicit null to clear assignee) is now the *default* behavior — no special option needed
- testExportNilFieldCanBeExplicitlyClearedAfterExport pins this contract at the public API boundary

## Files touched
- `SwiftSync/Sources/SwiftSync/Core.swift` (ExportOptions, exportObject(for:) overload)
- `SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift` (exportBlock)
- `SwiftSync/Tests/IntegrationTests/ExportTests.swift`
- `Demo/Demo/Features/TaskDetail/TaskDetailView.swift`
- `Demo/Demo/Features/Projects/ProjectsTabView.swift`
- `.agents/state.md`
