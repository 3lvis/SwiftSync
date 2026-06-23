# AGENTS.md

## Code Style Preferences

- Prefer pure functions that return values over void functions with side effects.
- Functions should return results rather than mutating state when possible.

## Code Comment Policy

- Do NOT add comments unless they are critical and required.
- Only add comments when they document:
  - Workarounds for bugs or limitations
  - Dangerous side effects
  - Non-obvious behavior that could cause issues

## Optimization Guidelines

- DO NOT extract helper functions unless they provide SIGNIFICANT net line reduction (at least 20+ lines saved).
- DO NOT refactor code just to "reduce duplication" if the net change is negligible (e.g., -2 lines).
- Extracting helpers that save only a few lines is NOT an improvement - it just moves code around.
- The original explicit code is often more readable than abstracted helpers.
- Focus on changes that have REAL impact: performance improvements, actual deletions, fixing bugs.

## Code Placement & Refactoring

Where a declaration lives is part of the design. These rules decide it; they are behavior-neutral —
a move builds and passes `swift test` (SwiftSync) **and** `swift test` (DemoCore) both before and after.

### File naming

- A file is named after a type that **actually exists in it** (`SyncPayload.swift` holds `SyncPayload`) —
  never a concept or a phantom type (`Push.swift` had no `Push`; `PushHistoryTokenStore.swift` had no
  `…Store` — both renamed to their real contained type). Don't let a file become a grab-bag of unrelated
  types — when one does (the old `Core.swift`), split it one public type per file. There is no
  `Core`/`Misc`/`Helpers`-style catch-all.
- `Type+Feature.swift` is **only** for extending a type you don't own (a stdlib/framework type from
  another module): `String+SnakeCase.swift`, `DateFormatter+Sync.swift`, `ModelContext+Sync.swift`.
- An extension on a type defined in **this** module is part of that type's definition, **not** a
  `+Feature` file: a protocol's default-impl extension, a type's `LocalizedError` conformance, and a
  small helper extension all live in the *same file as the type* they extend. Never hoist them out.

### No free functions — every function has an owner

- Home an internal helper on the type it naturally operates on, as an extension (snake-casing →
  `String`; a related-row fetch → `ModelContext`; dedupe → `Array`/`Sequence`).
- When the function has **no single operand** (it takes a payload *and* a model, or is an
  identity/namespace-level operation), home it as a `static` on the `SwiftSync` namespace enum.
- **Public macro-SPI** (functions `@Syncable`-generated code calls cross-module — must be `public`)
  goes on `SwiftSync` statics, **never** on a stdlib/model type. Homing it on `Dictionary`/the model
  protocol would force *that type's* public API to carry sync internals for every consumer.
- The only allowed free function is a control-flow wrapper with genuinely no operand that reads worse
  namespaced, kept `internal` so it pollutes nothing (`syncProfile`). Justify it explicitly or don't.

### When a type earns its own file vs. folds into a caller

Measure first — `grep -rn TypeName` repo-wide — and **distinguish library `Sources` references (which
decide the home) from test/consumer references (which are usage, not a home)**. Verify the claim; don't
assume from a type's name what calls it.

- **Multiple library callers** → its own file — *unless* the type is a subsystem's vocabulary or a
  protocol's parameter (a profiler's phase enum, an `OptionSet` a protocol method takes); that lives in
  the owner's file however many sites reference it. Call-site count guards against cramming into an
  *arbitrary* caller, not against co-locating with the conceptual owner. And if folding would bury a
  cohesive subsystem in a namespace/catch-all file, do the **reverse** — move the small installer/glue
  into the subsystem's own well-named file.
- **Exactly one library caller** → fold it into that caller's file (`SyncPayloadConvertible` → only the
  `SyncContainer.sync` overloads reference it → `SyncContainer.swift`; `SyncRelationshipSchemaDescriptor`
  → only the `SyncModelable` requirement → `SyncModelable.swift`). A public type still conformed to by
  consumers is fine to relocate — moving the *declaration* next to its one library caller doesn't change
  the public surface.
- **Zero library callers** (public API exercised only by consumers or by `@Syncable`-generated code) →
  categorize by *what calls it*, not by a runtime caller:
  - macro-generated-code SPI (e.g. `ExportState`, called only by the generated `export()`) homes with
    its SPI siblings in `MacroRuntimeSupport.swift` — same category as `exportEncodeValue`/`exportSetValue`.
  - a model-family protocol consumers conform to by hand keeps its own file alongside `SyncModelable`/
    `SyncUpdatableModel` — not macro-generated, so the macro file is the wrong home. But first confirm it
    is genuinely consumer-facing: a public protocol with zero library callers that the library never
    dispatches on is dead surface to remove, not a seam to keep.

- **Duplicated parallel logic is a correctness hazard, not just clutter.** When two types carry the same
  logic (a SwiftUI observer mirroring a plain publisher; a stub/real overload pair), a fix that lands in
  one copy silently leaves the twin broken — and the *untested* copy is exactly where the bug hides.
  Prefer eliminating the duplication (make one delegate to the other) over maintaining both in lockstep.

### Visibility follows location

- A relocation is also the moment to *audit*, not just move: is the symbol dead (no caller anywhere →
  delete), over-exposed (now single-file → tighten), or vestigial public API (zero library callers, never
  dispatched on → remove)? Moving code doesn't validate it — most of this session's dead code and stale
  docs rode in on structural moves that skipped the audit.
- Before removing public API, check git history for *why* it's unused — orphaned by a past refactor,
  superseded by a newer mechanism, or never used. "Currently unused" is not the justification; the *why*
  decides drop vs. preserve (superseded by an idiomatic equivalent → drop; a real capability with no
  replacement → keep, or absorb into the canonical type).
- When a symbol collapses to one file, tighten `internal` → `private`. Swift `private` reaches across
  same-file `extension`s of a type, so a `private static` on `SwiftSync` is still callable from other
  `extension SwiftSync` blocks in that file.
- `@testable import` exposes `internal`, **not** `private` — so `internal` is the floor for anything a
  separate-target test reads; don't drop those to `private`, and don't widen to `public` for tests' sake.

### Macro module boundary

`SyncableMacro.swift` lives in the **`MacrosImplementation`** plugin module (the compiler plugin) and
**cannot** hold a public runtime type. Runtime macro-SPI — the `public` declarations generated code calls
at runtime, including `ExportState` — lives in **`MacroRuntimeSupport.swift`** in the `SwiftSync` module.

## Docs: contracts, not snapshots

- Don't keep a doc that must be hand-synced to code — type/file/function lists, generated-code examples,
  diagrams of internals. It rots and misleads (we deleted `ARCHITECTURE.md` after it documented a removed
  lease, a removed protocol, and a deleted file). The truth lives where it can't drift: code + tests;
  targets in `Package.swift`; contracts/conventions here; public usage in `README`; how-to-layer-an-app
  in `docs/project/architecture.md`.
- Renaming or removing any symbol or file: grep the docs (`README`, `AGENTS.md`, `docs/**`) for
  references and fix them in the *same* change.

## Core Mantra

- Convention-first with explicit relationship paths at API boundaries.
- Parent-scoped sync requires explicit `relationship` key paths.
- Query relationship scoping requires explicit `relationship` + `relationshipID`.
- Payload semantics are strict:
  - absent key => ignore (no mutation)
  - explicit `null` => clear/delete

## Development Process (Scoped TDD)

- Strict TDD is required only for library changes in:
  - `SwiftSync/**`
  - `DemoBackend/**`
- TDD is required for behavior additions/changes:
  - write/update tests first
  - run tests and confirm failure for expected reason
  - implement and make tests pass
- Removals are TDD-exempt:
  - remove code first
  - run relevant tests
  - remove/update tests that validate intentionally removed behavior

### Demo app workflow (`Demo/Demo/**`)

- Strict TDD is not required.
- Verify changes with relevant tests when available.
- For UI or behavior changes in `Demo/Demo/**`, build the demo app before finishing the task.
- Use manual QA in the demo app as needed, but do not treat manual QA as a substitute for the required build step.

## Implementation Guidance

- Keep changes minimal and behavior-driven.
- Avoid inferring behavior from implementation details in tests; test expected contract.
- Keep diagnostics explicit and actionable when behavior cannot be resolved safely.
- For performance work, always record a before-change baseline on the same benchmark or profiling command before implementing the optimization, then re-run the same measurement after the change.
- When a bug appears and the correct fix is not yet known, follow `docs/project/bug-solving-playbook.md`.
- If a new bug is discovered while working on a base or integration branch, move that investigation onto a dedicated branch before debugging further.

## Roadmap

`docs/planning/world-class-roadmap.md` is the single living plan — the path from "very good" to world-class. Update it as work lands: strike through or delete completed items and keep only what's still open. The roadmap plus git history is the memory; there are no per-branch state files or capsules.

## Execution Safety

- Never do implementation work on `main` or `master`.
- If the current branch is `main` or `master`, stop and move all uncommitted changes onto a new branch before continuing any work.
- Use conventional branch naming with a lowercase slash prefix plus a short kebab-case slug.
- Preferred prefixes: `feature/`, `fix/`, `chore/`, `docs/`, `refactor/`, `spike/`.
- Branch names should describe the work, not the author or tool. Example: `fix/task-detail-refresh` or `refactor/project-machine-thinning`.
- Default all commands to sequential execution.
- Run commands in parallel only when they are independent and read-only.
- Never run mutating commands in parallel (git/worktree/index writes, file writes, build artifacts, caches, or derived data).
- Run build/test/codegen commands sequentially (for example `xcodebuild`, `swift test`, formatters, generators).
- For Git, run these sequentially only: `git add`, `git rm`, `git mv`, `git commit`, `git merge`, `git rebase`, `git cherry-pick`, `git checkout`, `git stash`, `git reset`, `git clean`.
- If a Git command fails due to `index.lock`, stop, remove the stale lock, and retry the same command sequentially.

## Code Formatting (swift-format)

- The package is formatted with `swift-format` (config: `.swift-format`).
- A tracked pre-commit hook in `.githooks/pre-commit` formats staged `*.swift` files automatically.
- **Enable it once per clone:** `./scripts/setup.sh` (or `git config core.hooksPath .githooks`).
- To format manually: `swift format --in-place --recursive SwiftSync/Sources SwiftSync/Tests` (Swift 6 toolchain; no standalone binary needed).
- CI enforces formatting by re-running `swift format --in-place` and failing on any diff — commits that skip the hook still fail the check.
- Use the Xcode 26.2 / Swift 6.x toolchain to match CI; older toolchains may format differently and cause spurious diffs.

## Pre-Commit Checkpoint

- This is a personally-responsible repo (`3lvis` remote), so the global rule applies: commit and open a
  **draft** PR proactively once a branch is a complete, green unit — no need to ask first or show the
  title/body. **Never merge without an explicit ask** — *except the doc-only fast path below.*
- **Doc-only fast path.** A PR whose changes are *only* `**.md` / `docs/**` skips the heavy CI
  (`paths-ignore` in `ci.yml` + `ios-regression.yml`), so no required checks report. Because
  `enforce_admins` is off on `master`, such a PR may be **opened and admin-merged immediately without
  asking** — `gh pr merge <n> --squash --admin --delete-branch`. This is the *only* merge allowed without
  an explicit ask. A mixed doc+code PR runs full CI and follows the normal gate (green, then ask).
- Before every commit:
  - run `git status --short`
  - confirm only intended files are staged
  - then run the commit command (sequentially)
- The pre-commit hook reformats and re-stages fully-staged `*.swift` files at commit time, so committed content may differ from what `git status` showed; partially-staged files are skipped (format them manually).
- Do NOT add attribution footer to commits:

  ```
  🤖 Generated with [Claude Code](https://claude.com/claude-code)

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```

## iOS Test Policy

- Default: run `swift test` (macOS/SPM) only.
- Exception: if a task changes `Demo/Demo/**`, run the relevant demo app build even if the user did not explicitly ask for `xcodebuild`.
- CI is split by the draft/ready signal:
  - **Every push (draft included)** runs the fast tier in `ci.yml`: swift-format, macOS `swift test` (×3 packages), the warnings gate, doc-links, and the perf subset.
  - **Only when a PR is marked ready for review** does the slow simulator tier in `ios-regression.yml` run — one `iOS Simulator Tests` job that runs both the `DemoUITests` UI suite and the iOS-specific dirty-tracking regression (`DirtyTrackingGapTests`) on a simulator. It skips on drafts (a skipped check still reports success) and there is no master-push run — this tier is pre-merge only.
- So mark a PR **ready** to trigger the `iOS Simulator Tests` gate, then verify it green before merging. If a task touches `MacrosImplementation/`, `MacroRuntimeSupport.swift`, or the core sync engine (`SyncContainer`/`ModelContext+Sync`), note in the plan that marking the PR ready will run that simulator tier.

### UI tests are a last resort (very expensive)

A `DemoUITests` test boots a simulator and builds the app — the costliest thing in CI. Keep one only when nothing cheaper can catch the regression.

- **A UI test owns its timeouts inline.** No shared timeout constant across tests; each `waitForExistence`/`waitForNonExistence` carries a value sized for that test's own operation, at the call site.
- **No green-at-birth tests.** A test earns its place only by having been red before the fix it guards (the red-first rule, applied to UI tests too). A test that passed at creation, guarding no demonstrated failure, is removed.
- **Prefer the cheapest layer that reproduces the failure.** Before adding or keeping a UI test, try to make the core failure reproduce as a DemoCore/DemoBackend/SwiftSync unit test. If a unit catches it, the UI test is redundant — drop it (precedent: the dirty-tracking regression was driven down from a UI test into `DirtyTrackingGapTests`).
- **Keep a UI test only with a strong, documented reason** — it exercises something units genuinely can't (view hierarchy, cross-screen navigation, a SwiftUI binding/reactivity path, a gesture/dismiss affordance) and you tried and failed to pin it to a unit. State the reason in a one-line comment on the test.
- Ongoing systematic effort + per-test trial log: `docs/planning/ui-test-trial.md`.
