# State Capsule

## Plan

- [x] Branch off master onto `chore/xcode-26-5-and-perf` (carries staged transition-doc deletion)
- [x] Verify local toolchain = Xcode 26.5 / Swift 6.3.2 (already current; nothing to install)
- [x] Scope the test-target compile break: 102 `SendingRisksDataRace` errors in SyncTests.swift + FetchStrategyBenchmarkTests.swift
- [x] Root-cause: `SwiftSync.sync(...)` is nonisolated-async taking non-Sendable `ModelContext`; @MainActor test code "sends" context across regions. Library compiles; only tests fail.
- [x] DECISION: user chose full isolation refactor (thread `#isolation` through async sync API)
- [x] Thread `isolation: isolated (any Actor)? = #isolation` through sync overloads + acquireSyncLease + withRelationshipLookupCache (API.swift)
- [x] Add isolation param to applyRelationships protocol reqs + defaults (Core.swift) and macro output (MacrosImplementation)
- [x] Update macro-expansion snapshot test (SyncableMacroDiagnosticsTests)
- [x] Fix all ~18 hand-written `applyRelationships` conformances in test files (old signature no longer satisfied the requirement -> no-op default silently ran -> relationships skipped)
- [x] Get test target compiling under Swift 6.3.2 + full suite green (149 tests, 0 failures, 9 benchmark skips)
- [ ] Commit + push branch for review
- [ ] PERF item 2: re-run demo-shaped sqlite+10k SAMPLES=5, confirm relationship win stable
- [ ] PERF item 3: memory vs sqlite at 1k/10k/50k for global paths
- [ ] PERF item 1: Instruments Time Profiler + Points of Interest on sqlite+10k (signposts already exist in SyncPerformanceProfiler.swift)
- [ ] PERF item 4: write product-boundary section into docs/planning/performance-attribution-follow-ups.md, then clear/remove

## Last known state

Library + tests build on Xcode 26.5 / Swift 6.3.2 with -strict-concurrency=complete preserved. Full suite green (149 tests, 0 failures). Benchmarks (perf items) not yet run.

## Decisions (don't revisit)

- All 4 perf-attribution items are unstarted; underlying numbers were captured in a prior session but follow-ups never run.
- Proper fix for 6.3.2 strictness = thread `isolation: isolated (any Actor)? = #isolation` through async `sync` API; cascades into `applyRelationships` protocol requirement in Core.swift + macro in MacrosImplementation -> strict TDD + iOS-regression trigger. Large.
- Lighter fix = relax test target concurrency. But project deliberately set `-strict-concurrency=complete` on ALL targets + `swiftLanguageModes: [.v6]`, so this fights project intent.
- Replaced a stale state.md (completed export-API task) with this capsule.
- CI NOT bumped to Xcode 26.5: the isolation changes (`#isolation`/`isolated`) compile on Swift 6.2 too, so CI on Xcode_26.2 stays green. Xcode 26.5 likely needs a macOS 26 runner (local is macOS 26; GitHub CI is macos-15) — bumping risks red CI. Left as an open question for review.
- API-COMPAT NOTE: adding isolation to the `applyRelationships` protocol requirement is source-breaking for external hand-written `SyncUpdatableModel` conformances (they must add the isolation param). `@Syncable` users are unaffected (macro regenerates).

## Files touched

- .agents/state.md (replaced)
- docs/planning/swiftsync-repo-transition.md (staged deletion, carried from master)
