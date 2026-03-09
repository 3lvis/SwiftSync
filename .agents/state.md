# State Capsule

## Plan

- [x] Move the current uncommitted docs work off `main` onto a new feature branch before continuing.
- [x] Update `README.md` to replace the outdated `SyncQueryPublisher` Combine example with the current Observation-based usage.
- [x] Review the README change for accuracy and update this state capsule with the final status.

## Last known state

current branch is `refresh-docs`; README updated and reviewed; no tests run because this was a documentation-only change

## Decisions (don't revisit)

- Add the new rule in the workflow/safety section rather than the feature-branch lifecycle section so it is encountered before implementation work begins.
- Create a docs-focused branch before any further edits so the new branch-safety rule is followed immediately.

## Files touched

- .agents/state.md
- AGENTS.md
- README.md
