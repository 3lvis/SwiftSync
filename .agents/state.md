# State Capsule

## Plan

- [x] Create a simple planning doc for the Ariadne app that another agent can continue from
- [x] Review the planning doc for clarity, scope, and handoff usefulness

## Last known state

Ariadne planning doc added and reviewed for handoff clarity; no tests run

## Decisions (don't revisit)

- Work on a feature branch because implementation on `master` is disallowed
- Follow library TDD for changes in `SwiftSync/**`
- Decide cleanup order from current code and test usage rather than renaming surfaces blindly
- Remove the bulk export API entirely rather than preserving an internal helper
- Make the public object-export API container-centric for consistency with `sync`
- Keep `REUSABLE_AGENTS.md` generic enough for other iOS/SwiftData repos, with placeholders where projects will need local policy
- Include reusable process knowledge directly in the file rather than leaving critical guidance in companion docs
- Keep the Ariadne plan simple, implementation-focused, and easy for another agent to resume

## Files touched

- .agents/state.md
- docs/planning/ariadne-app-plan.md
