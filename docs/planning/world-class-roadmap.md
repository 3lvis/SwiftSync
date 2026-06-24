# World-Class Roadmap

Goal: take SwiftSync from "very good SwiftData library" to world-class. This is the source of truth
for open product work. Keep only work that is still actionable; completed work belongs in git history.

Companion audits:

- [`comment-audit.md`](comment-audit.md) — remaining comment cleanup outside the library core.
- [`performance-attribution-follow-ups.md`](performance-attribution-follow-ups.md) — optimizations that
  require benchmark evidence before implementation.

## Now

_Nothing actively committed — open work is evidence-gated below or deferred to first release._

## Evidence-gated or deferred

- [ ] Define app-owned retention for already-pushed local history when a shipped consumer shows material
      disk growth or recovery latency. Local transactions use the app's default author, so SwiftSync must
      not delete them automatically: another history consumer may still need them. Any future cleanup
      needs a safe watermark covering every consumer, not only SwiftSync's per-model pushed tokens.
- [ ] Finish the sync-protocol prior-art scan only before hardening the pull/cursor contract further.
      Failure-model research is complete; do not perform research without a pending contract decision.
- [ ] Design offline-safe queue migrations and versioning when a shipped consumer has persisted pending
      changes to protect. Before that point the pre-1.0 format may break freely.
- [ ] Revisit nested-object relationship fetch narrowing only when a nested-object-heavy benchmark shows
      full-table fetches dominating. Foreign-key relationship paths are already narrowed.
- [ ] Revisit automatic `.preserveValueOnDeletion` only if Swift gains a macro role capable of attaching
      an attribute to an existing stored property. Runtime validation is the current contract.
- [ ] Add authorization and ownership checks in a real authenticated backend. The demo has no principals;
      client-minted ids are not an authorization boundary.
- [ ] Harden `/sync/upload` upserts against a same-`public_id` write race only once a real concurrent
      backend exists. Distinct rows can't collide — client-minted UUIDs are unique per row — so the only
      conflict is a client racing its own retry of the *same* row, which is impossible in the
      single-threaded demo where sequential update-else-create already converges. Revisit with
      `INSERT ... ON CONFLICT(public_id) DO UPDATE` (or one-transaction conflict recovery) then.
- [ ] Add sync lifecycle observability (a multi-consumer `events()` stream) only when a real *out-of-band*
      consumer needs it — an autonomous background drain, or a status view spanning many concurrent syncs.
      For the current explicit-`await` model the call boundary already gives the caller start, completion,
      duration, and failure (`throws`); counts are a `fetch` away. The predecessor `3lvis/Sync` shipped for
      years on an `error`-only completion and never surfaced counts/duration. Don't build a stream until a
      consumer genuinely can't get the same by awaiting the call.

## First release

- [ ] Document the intended public surface and the macro-runtime extension points that generated code
      calls across module boundaries.
- [ ] After the first tag exists, gate source compatibility with
      `swift package diagnose-api-breaking-changes <last-tag>` and an explicit allowlist for intentional
      breaks.
