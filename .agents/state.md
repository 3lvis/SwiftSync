# State Capsule

## Plan
- [x] Consolidate overlapping safety sections in `AGENTS.md` into a single execution safety policy.
- [x] Add a compact required-workflow summary to the `.agents` protocol section.

## Last known state
docs updated (AGENTS safety + required workflow simplified)

## Decisions (don't revisit)
- Use explicit load state machines (`idle/loading/loaded/error`) rather than boolean loading flags for demo screen fetch flows.
- Keep save/mutation failures separate from load-state errors so retry copy stays context-specific.
- Strict TDD policy applies only to `SwiftSync/**` and `DemoBackend/**`; removals are code-first with post-change test validation.

## Files touched
- .agents/state.md
- AGENTS.md
