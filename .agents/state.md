# State Capsule

## Plan
- [x] Consolidate module structure: merge Core + SwiftDataBridge + Macros + TestingKit into single SwiftSync target
- [x] Update Package.swift — single SwiftSync product/target; remove Core, SwiftDataBridge, Macros, TestingKit
- [x] Update CoreTests imports: @testable import Core → @testable import SwiftSync
- [x] Unify ExportKeyStyle + SyncInputKeyStyle → single KeyStyle enum; delete SyncInputKeyStyle
- [x] Rename SyncContainer.inputKeyStyle → keyStyle (type: KeyStyle); update all sync call sites
- [x] Make ExportState non-constructable externally: keep public enum with static enter/leave (thread-local state)
- [x] Update SyncUpdatableModel: exportObject(using:) drops state: param; macro generates clean public method
- [x] Move dateFormatter to SyncContainer; ExportOptions.defaultDateFormatter() made internal
- [x] Add exportObject(for:relationshipMode:includeNulls:) on SyncUpdatableModel protocol extension
- [x] Update API.swift export statics: remove ExportState allocation; call exportObject(using:) directly
- [x] Update MacrosImplementation: generated exportObject uses ExportState.enter/leave static API; child calls use exportObject(using:)
- [x] Update ExportTests: regression guard, 2 test methods, add 2 new container-derivation tests
- [x] Update demo call sites: TaskDetailView x3, ProjectsTabView x1
- [x] Build Demo (BUILD SUCCEEDED), run full suite (155 tests passing)
- [x] Update docs/planning/export-simplification.md execution checklist

## Last known state
155/155 tests green / Demo BUILD SUCCEEDED

## Decisions (don't revisit)
- No backwards compat: ExportKeyStyle, SyncInputKeyStyle removed entirely (no typealias)
- ExportState stays `public enum` (not struct) so macro-generated code in client modules can call static enter/leave; init is blocked via enum (no cases)
- Thread-local storage (Thread.current.threadDictionary) used to carry ExportState across recursive exportObject(using:) calls without exposing state in the protocol
- exportObject(for:container:) lives in SyncUpdatableModel protocol extension in Core.swift — no module boundary issue since Core is now part of SwiftSync
- ExportOptions.defaultDateFormatter() is internal; ExportOptions.init uses nil-defaulted dateFormatter? param to avoid internal default arg restriction
- Core + SwiftDataBridge + Macros + TestingKit all folded into SwiftSync/Sources/SwiftSync/ — ObjCExceptionCatcher and MacrosImplementation remain separate targets (required by Swift toolchain)

## Files touched
- `Package.swift`
- `SwiftSync/Sources/SwiftSync/Core.swift` (moved from Core/)
- `SwiftSync/Sources/SwiftSync/SyncDateParser.swift` (moved from Core/)
- `SwiftSync/Sources/SwiftSync/API.swift` (moved from SwiftDataBridge/)
- `SwiftSync/Sources/SwiftSync/SyncableMacro.swift` (moved from Macros/, import Core stripped)
- `SwiftSync/Sources/SwiftSync/Fixtures.swift` (moved from TestingKit/)
- `SwiftSync/Sources/SwiftSync/SyncContainer.swift`
- `SwiftSync/Sources/SwiftSync/ReactiveQuery.swift`
- `SwiftSync/Sources/SwiftSync/SyncQueryPublisher.swift`
- `SwiftSync/Sources/MacrosImplementation/SyncableMacro.swift`
- `SwiftSync/Tests/CoreTests/DateParserTests.swift`
- `SwiftSync/Tests/CoreTests/SyncPayloadCoercionTests.swift`
- `SwiftSync/Tests/CoreTests/SyncPayloadDeepPathTests.swift`
- `SwiftSync/Tests/CoreTests/SyncPayloadKeyStyleTests.swift`
- `SwiftSync/Tests/IntegrationTests/ExportTests.swift`
- `SwiftSync/Tests/IntegrationTests/IntegrationTests.swift`
- `Demo/Demo/Features/TaskDetail/TaskDetailView.swift`
- `Demo/Demo/Features/Projects/ProjectsTabView.swift`
- `docs/planning/export-simplification.md`
