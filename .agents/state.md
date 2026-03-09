# State Capsule

## Plan

- [x] Review `docs/project/faq.md` against current code/docs and identify stale answers or links.
- [x] Update `docs/project/faq.md` to remove outdated claims and align wording with current behavior.
- [x] Review the FAQ changes and update this state capsule with the final status.

## Last known state

current branch is `refresh-docs`; FAQ updated and reviewed; no tests run because this was a documentation-only change

## Decisions (don't revisit)

- Add the new rule in the workflow/safety section rather than the feature-branch lifecycle section so it is encountered before implementation work begins.
- Create a docs-focused branch before any further edits so the new branch-safety rule is followed immediately.
- While touching the FAQ, fix numbering gaps caused by removed questions so the document reads cleanly.

## Files touched

- .agents/state.md
- AGENTS.md
- README.md
- docs/project/faq.md
