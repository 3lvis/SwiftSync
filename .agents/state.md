# State Capsule

## Plan

- [x] Add an explicit branch-safety rule to `AGENTS.md` forbidding work on `main`/`master` and requiring a new branch before continuing.
- [x] Review the updated wording for clarity and consistency with the rest of `AGENTS.md`.
- [x] Update this state capsule with the final status for the documentation change.

## Last known state

`AGENTS.md` updated and reviewed; current branch is still `main`; no tests run because this was a documentation-only change

## Decisions (don't revisit)

- Add the new rule in the workflow/safety section rather than the feature-branch lifecycle section so it is encountered before implementation work begins.

## Files touched

- .agents/state.md
- AGENTS.md
