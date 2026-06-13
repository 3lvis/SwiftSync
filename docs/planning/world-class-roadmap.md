# World-Class Roadmap

Goal: take SwiftSync from "very good SwiftData library" to world-class. This file is
the source of truth for that effort. Each open item is sized to be a single worktree
branch. Work through them systematically; mark complete by deleting the line (per
`docs/planning` cleanup rules) once merged.

## Baseline (2026-06-14)

- Root `swift test`: 149 tests pass, 9 benchmark skips. DemoCore: 21. DemoBackend: 21.
- Builds emit warnings (generated-macro warnings in root; Swift 6 sendability warnings
  in DemoCore). Not warning-clean.
- swift-tools `6.2`, language mode `.v6`. Platforms iOS 17 / macOS 14.
- CI (`ci.yml`): swift-format check + `swift test` on SwiftSync/DemoBackend/DemoCore.
  No warnings gate, no docs gate, no perf gate.

## Reference targets

- `code/3lvis/ios/Networking` — the version/platform north star: swift-tools `6.2`,
  `swiftLanguageModes: [.v6]`, platforms `iOS(.v18), macOS(.v15), tvOS(.v18), watchOS(.v11)`.
  SwiftSync matches on tools + language mode; the gap is platforms.

## Resolved decisions

- Platforms: **iOS 18 + macOS 15 only** (no tvOS/watchOS). Matches Networking's Swift
  version + iOS 18 floor; covers all tested surface.
- `migrating-from-sync.md`: **remove the two dangling links** (docs/README.md); defer any
  migration guide.

## Open decisions (resolve before/while doing the items they block)

- [ ] Decide intended public extension points: which low-level sync helpers
      (`syncApplyToOneForeignKey`, `exportSetValue`, `ExportState`, …) are deliberate
      seams vs. accidentally-public implementation detail.
- [ ] Decide SwiftData-modern stance per feature (`#Unique`, `#Index`, history API,
      custom `DataStore`, `#Expression`): adopt, interop-and-document, or out-of-scope.

## Open items

### Phase 0 — Foundation: version + platform parity

- [ ] Bump SwiftSync `Package.swift` platforms to iOS 18 / macOS 15; confirm swift-tools
      6.2 + `swiftLanguageModes: [.v6]` everywhere.
- [ ] Align DemoCore, DemoBackend, and the `Demo` app project to the same platform floor;
      run `swift test` on all packages and build the Demo app to confirm green.

### Phase 1 — Warning-clean under Swift 6.x

- [ ] Eliminate generated-macro warnings in the SwiftSync root build.
- [ ] Eliminate Swift 6 sendability warnings in DemoCore (prefer `actor`/real isolation
      over `@unchecked Sendable`, per iOS conventions).
- [ ] Audit DemoBackend and the Demo app for build warnings; drive to zero.
- [ ] Turn on `-warnings-as-errors` (or Swift 6.2 upcoming-feature/warning controls) for
      library targets once clean, so regressions can't reintroduce warnings.

### Phase 2 — Fix doc drift

- [ ] Rewrite `ARCHITECTURE.md` to match the real Package.swift module layout
      (SwiftSync + ObjCExceptionCatcher libraries, MacrosImplementation macro, test targets).
- [ ] Remove the two `migrating-from-sync.md` dangling links in `docs/README.md`.
- [ ] Sweep all docs for dead cross-links and stale claims; add a link-check to CI (Phase 6).

### Phase 3 — DocC + publishable API documentation

- [ ] Add a DocC catalog to the SwiftSync target with a landing page and curated topics.
- [ ] Document every public symbol surviving the API-surface tightening (Phase 5).
- [ ] Add a CI job that builds DocC (and optionally publishes to GitHub Pages).

### Phase 4 — Explicit SwiftData-modern stance

- [ ] Write a doc stating SwiftSync's position on `#Unique`, `#Index`, the history API,
      custom `DataStore`, and `#Expression`/richer predicates — interop rules + rationale.
- [ ] Adopt the features that genuinely improve the library (e.g. `#Index` on sync keys),
      with red-first tests; document the rest as interop-only.

### Phase 5 — Tighten the public API surface

- [ ] Audit all `public` symbols; demote low-level sync helpers to `internal`/`package`
      unless the decision marks them as intended extension points.
- [ ] Document the intended public surface and supported extension points in DocC.

### Phase 6 — CI gates for world-class hygiene

- [ ] Add a warnings gate (depends on Phase 1).
- [ ] Add a docs gate: DocC build success + doc link-check (depends on Phases 2–3).
- [ ] Un-skip a small, fast benchmark subset and add a thresholded perf-regression gate;
      `log()` anything intentionally excluded so coverage isn't silently truncated.

### Phase 7 — Define the production-sync story (design-first)

- [ ] Write a design doc framing the gap from "sync-assist" to "production sync":
      conflict resolution, offline mutation queue, retry/backoff, observability hooks,
      schema-migration policy, history-based local change export, CloudKit coexistence,
      and versioned API stability.
- [ ] Break each accepted area into its own dedicated implementation item once designed.
</content>
</invoke>
