# State Capsule

## Plan

- [x] Update `docs/project/reactive-reads.md` to replace stale `SyncQueryPublisher` Combine guidance and align reload behavior wording with the current implementation.
- [x] Review the reactive-reads doc changes for accuracy and consistency with `README.md`.
- [x] Update this state capsule with the final status.

## Last known state

current branch is `refresh-docs`; reactive-reads updated and reviewed; no tests run because this was a documentation-only change

## Decisions (don't revisit)

- Add the new rule in the workflow/safety section rather than the feature-branch lifecycle section so it is encountered before implementation work begins.
- Create a docs-focused branch before any further edits so the new branch-safety rule is followed immediately.
- While touching the FAQ, fix numbering gaps caused by removed questions so the document reads cleanly.
- Keep `reactive-reads.md` aligned with the README's Observation-based `SyncQueryPublisher` example to avoid split-brain docs.

## Files touched

- .agents/state.md
- AGENTS.md
- README.md
- docs/project/faq.md
- docs/project/reactive-reads.md
