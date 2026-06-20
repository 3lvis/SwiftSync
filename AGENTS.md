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
  title/body. **Never merge without an explicit ask.**
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
- So mark a PR **ready** to trigger the `iOS Simulator Tests` gate, then verify it green before merging. If a task touches `Core.swift`, `MacrosImplementation/`, or `SyncableMacro.swift`, note in the plan that marking the PR ready will run that simulator tier.

### UI tests are a last resort (very expensive)

A `DemoUITests` test boots a simulator and builds the app — the costliest thing in CI. Keep one only when nothing cheaper can catch the regression.

- **A UI test owns its timeouts inline.** No shared timeout constant across tests; each `waitForExistence`/`waitForNonExistence` carries a value sized for that test's own operation, at the call site.
- **No green-at-birth tests.** A test earns its place only by having been red before the fix it guards (the red-first rule, applied to UI tests too). A test that passed at creation, guarding no demonstrated failure, is removed.
- **Prefer the cheapest layer that reproduces the failure.** Before adding or keeping a UI test, try to make the core failure reproduce as a DemoCore/DemoBackend/SwiftSync unit test. If a unit catches it, the UI test is redundant — drop it (precedent: the dirty-tracking regression was driven down from a UI test into `DirtyTrackingGapTests`).
- **Keep a UI test only with a strong, documented reason** — it exercises something units genuinely can't (view hierarchy, cross-screen navigation, a SwiftUI binding/reactivity path, a gesture/dismiss affordance) and you tried and failed to pin it to a unit. State the reason in a one-line comment on the test.
- Ongoing systematic effort + per-test trial log: `docs/planning/ui-test-trial.md`.
