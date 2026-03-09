# State Capsule

## Plan

- [x] Create planning docs for nested to-many dirty-tracking coverage gap and fetch-strategy load validation.
- [x] Review the new planning docs for format compliance and repo alignment.
- [x] Refine the nested dirty-tracking planning doc with must-do implementation steps only.
- [x] Refine the fetch-strategy planning doc with benchmark-first resolution steps and solution shape.

## Last known state

planning docs updated; nested dirty-tracking and fetch-strategy plans now include concrete must-do work and solution shape; no tests or builds run for this docs-only change

## Decisions (don't revisit)

- Use `docs/planning/` for both documents because the repo already reserves that directory for active planning artifacts.
- Keep both docs focused on problem framing (`why` and `what`) and explicitly defer implementation details (`how`) to later work.
- Keep both the direct nested-path parity fix and shared to-many deduplication in scope for the eventual implementation.
- When implementation starts in `SwiftSync/**`, follow strict TDD and note that touching `Core.swift` means iOS regression will run on merge.
- Resolve fetch-strategy work in this order: benchmark first, optimize feasible paths second, document or expose options for the remaining constrained paths third.

## Files touched

- .agents/state.md
- docs/planning/nested-to-many-dirty-tracking-gap.md
- docs/planning/fetch-strategy-under-load.md
