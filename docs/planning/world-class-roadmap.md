# World-Class Roadmap

Goal: take SwiftSync from "very good SwiftData library" to world-class. This is the source of truth
for open product work. Keep only work that is still actionable; completed work belongs in git history.

Companion audits:

- [`comment-audit.md`](comment-audit.md) — remaining comment cleanup outside the library core.
- [`performance-attribution-follow-ups.md`](performance-attribution-follow-ups.md) — optimizations that
  require benchmark evidence before implementation.

## Now

- [ ] **Make demo-backend upload upserts atomic.** `/sync/upload` currently looks up `public_id` and then
      chooses insert or update. Replace that race with `INSERT ... ON CONFLICT(public_id) DO UPDATE`, or
      recover a uniqueness conflict inside one transaction. The demo is single-threaded today, but the
      endpoint contract promises idempotent upserts and should model the concurrency-safe shape.

- [ ] **Add sync lifecycle observability.** Provide a multi-consumer `events()` stream for sync start and
      completion, applied/stale/rejected outcomes, counts, and duration. Errors continue to bubble and
      per-row failures remain consumer-owned; the stream observes outcomes rather than persisting policy.

- [ ] **Decide the SwiftData-modern stance per feature.** Classify `#Unique`, `#Index`, History, custom
      `DataStore`, and `#Expression` as adopted, interoperable with documented constraints, or out of
      scope. Do not expand the public API until each choice has a demonstrated consumer need.

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

## First release

- [ ] Document the intended public surface and the macro-runtime extension points that generated code
      calls across module boundaries.
- [ ] After the first tag exists, gate source compatibility with
      `swift package diagnose-api-breaking-changes <last-tag>` and an explicit allowlist for intentional
      breaks.
