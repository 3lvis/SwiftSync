# AGENTS.md

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

## docs/planning Rules

1. Cleanup on new task start

- Before adding new work, remove completed or stale items.
- Remove: `[x]`, `[~]`, `completed`, `done`, `superseded`, `scheduled`.
- Keep only active items.

2. Required todo format

- Every planning file must include `## Open items`.
- Open items must use unchecked checkboxes only: `- [ ] <task>`.
- Items must be short, actionable, and implementation-focused.

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

## Pre-Commit Checkpoint

- **Do not commit unless the user explicitly asks.**
- Before every commit:
  - run `git status --short`
  - confirm only intended files are staged
  - then run the commit command (sequentially)

## Agent RAM Persistence Protocol (.agents)

### Why

Agents remember two things:

- **Disk context** = what's in the repo (persists via git)
- **RAM context** = the current working memory (gets lost if the agent stops or you switch machines)

RAM context is: the plan, which steps are done, which was in-progress when stopped, and any decisions that cost time to reach.

### Goal

Make work **restart-safe** by writing the agent's RAM into the repo.

---

## Where it lives

Put all continuity files in **`.agents/`**:

- **`.agents/state.md`** — the plan and its execution state (source of truth)

Keep it committed and current while working.

---

## 1) `.agents/state.md` (State Capsule)

**Purpose:** survive an abrupt stop — usage cap, crash, machine switch — and resume exactly where work left off.

**Write the plan before implementation starts. Update checkboxes as steps complete. Never wait until "on stop" to fill this in — that moment may never come.**

**Rules:**

- Write the full plan upfront as a checkbox list
- Mark steps complete (`[x]`) immediately after finishing — in the same commit as the code for that step
- Mark the in-progress step `[~]` with a brief trailing note if it's partially done
- Update `Last known state:` after any test or build run
- Decisions that cost time to reach go in **Decisions** — not in commit messages, not in your head
- Amend the plan freely if reality diverges — the plan is a map, not a contract

**Template:**

```md
# State Capsule

## Plan

- [x] Step already done
- [~] Step in progress — brief note on exactly where it stopped
- [ ] Step not started yet
- [ ] Step not started yet

## Last known state

tests green / build failing / untested

## Decisions (don't revisit)

- <decision> — <why>

## Files touched

- path
```

---

## Operating procedure

### Start (every agent run)

1. Read `.agents/state.md`
2. Run `git status` and `git log --oneline -5` to orient
3. Resume from the `[~]` step if one exists, otherwise the first `[ ]` step in the Plan

### During work

- **Before starting each step** — mark it `[~]` in the Plan
- **After completing each step** — mark it `[x]`; include the `state.md` update in the same commit as the code for that step
- **After any test or build run** — update `Last known state:`
- **When a non-obvious decision is made** — add it to **Decisions** immediately

### On stop

No special procedure needed. If the plan was kept current during work, `state.md` already reflects reality.

---

## Memory Lifecycle: Feature Branches

`.agents/` is **branch-scoped**. It lives and dies with the feature branch.

### Rules

- `.agents/` is only valid on feature branches — never on `main`.
- Prefer not to include `.agents/` in PR diffs, but if it lands on `main`, CI will clean it up automatically.
- Each feature branch owns its own isolated `.agents/` — no cross-branch memory.
- `.agents/` is automatically deleted from `main` by the **Purge .agents on main** GitHub Actions workflow (`.github/workflows/purge-agents.yml`). No manual cleanup is required.

### Lifecycle

| Event                              | Action                                                                          |
| ---------------------------------- | ------------------------------------------------------------------------------- |
| Start feature branch               | Create `.agents/state.md` and write the full plan before touching code          |
| Switch machines mid-task           | Read `.agents/state.md` to restore context — no lost work                       |
| Usage cap hit mid-task             | Read `.agents/state.md` on resume — continue from the `[~]` or first `[ ]` step |
| PR merged / branch closed          | CI purges `.agents/` automatically on next push to `main`                       |
| Hard context switch (abandon task) | Delete `.agents/` — stale state misleads more than it helps                     |

### Why not gitignore it?

Gitignoring `.agents/` defeats the "switch machines" goal. The files must be committed to survive machine switches. The tradeoff is: commit freely on feature branches, CI cleans up on merge.

---

## iOS Test Policy

- Default: run `swift test` (macOS/SPM) only.
- Exception: if a task changes `Demo/Demo/**`, run the relevant demo app build even if the user did not explicitly ask for `xcodebuild`.
- iOS regression runs automatically post-merge via `ios-regression.yml` — that is the gate.
- If a task touches `Core.swift`, `MacrosImplementation/`, or `SyncableMacro.swift`, note in
  the plan that the iOS regression will run on merge.
