# State Capsule

## Plan
- [x] Refocus manual-conformance doc on data manipulation use cases in `make`/`apply`.
- [x] Add a realistic normalization/derivation example that transforms payload data before assignment.
- [x] Verify the updated examples still preserve SwiftSync payload semantics and operation-gated relationship behavior.

## Last known state
untested (docs-only revision completed)

## Decisions (don't revisit)
- Keep this guidance out of `README.md` and place it only in a dedicated project doc, per user request.
- Emphasize transformation/normalization in `make`/`apply` as the primary manual-conformance motivation.

## Files touched
- .agents/state.md
- docs/project/manual-syncupdatablemodel.md
