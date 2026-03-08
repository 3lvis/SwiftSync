# State Capsule

## Plan
- [x] Update `AGENTS.md` to scope strict TDD to library changes and exempt removals.

## Last known state
docs updated (AGENTS policy now scoped to library TDD and removal exemption)

## Decisions (don't revisit)
- Use explicit load state machines (`idle/loading/loaded/error`) rather than boolean loading flags for demo screen fetch flows.
- Keep save/mutation failures separate from load-state errors so retry copy stays context-specific.
- Strict TDD policy applies only to `SwiftSync/**` and `DemoBackend/**`; removals are code-first with post-change test validation.

## Files touched
- .agents/state.md
- AGENTS.md
