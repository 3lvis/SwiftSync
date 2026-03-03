# AGENTS.md

## Core Mantra

- Convention-first, explicit only for ambiguity.
- Parent relationship inference is the default behavior.
- `parentRelationship` is required only when multiple parent relationships are valid candidates.
- Payload semantics are strict:
  - absent key => ignore (no mutation)
  - explicit `null` => clear/delete

## Development Process (Strict TDD)

- Always work test-first.
- For any behavior change or bug fix:
  - write or update tests first
  - run tests to confirm they fail for the expected reason
  - only then implement code to make tests pass
- If API surface is missing, add the smallest API needed to express the test first.
- Do not write implementation first and then backfill tests.
- Prefer regression tests that pin behavior at the public API boundary.
- After implementation, run relevant targeted tests and then broader suite as needed.

## Implementation Guidance

- Keep changes minimal and behavior-driven.
- Avoid inferring behavior from implementation details in tests; test expected contract.
- Keep diagnostics explicit and actionable when behavior cannot be resolved safely.

## Git Command Safety

- Default all Git commands to sequential execution.
- Only parallelize Git commands when they are clearly read-only and no other Git command in the same step may write repo metadata.
- Never run Git index- or worktree-mutating commands in parallel.
- Run these sequentially only: `git add`, `git rm`, `git mv`, `git commit`, `git merge`, `git rebase`, `git cherry-pick`, `git checkout`, `git stash`, `git reset`, `git clean`.
- Do not use parallel tool calls for multiple Git commands when any command may write `.git/index`, `.git/HEAD`, refs, or the worktree.
- If a Git command fails due to `index.lock`, stop, remove the stale lock, and retry the same command sequentially.

## Parallel Command Safety

- Default commands that mutate shared state to sequential execution.
- Never run commands in parallel if they may write to the same workspace files, build artifacts, caches, or derived data.
- Run build/test/codegen commands sequentially (for example `xcodebuild`, `swift test`, formatters, generators).
- If a failure could be caused by contention, rerun the same command alone before debugging deeper.

## `multi_tool_use.parallel` Usage Rules

- Use parallel only for read-only exploration and independent commands.
- Good parallel examples: `rg`, `sed`, `cat`, `ls`, `git diff`, `git show`, `git status`.
- Do not use parallel when any command in the group:
  - writes files
  - mutates git state
  - runs build/test tooling
  - depends on another command's output in that same group

## Pre-Commit Checkpoint

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

| Event | Action |
|---|---|
| Start feature branch | Create `.agents/state.md` and write the full plan before touching code |
| Switch machines mid-task | Read `.agents/state.md` to restore context — no lost work |
| Usage cap hit mid-task | Read `.agents/state.md` on resume — continue from the `[~]` or first `[ ]` step |
| PR merged / branch closed | CI purges `.agents/` automatically on next push to `main` |
| Hard context switch (abandon task) | Delete `.agents/` — stale state misleads more than it helps |

### Why not gitignore it?

Gitignoring `.agents/` defeats the "switch machines" goal. The files must be committed to survive machine switches. The tradeoff is: commit freely on feature branches, CI cleans up on merge.

---

## iOS Test Policy

- Default: run `swift test` (macOS/SPM) only. Never run `xcodebuild` unless explicitly asked.
- iOS regression runs automatically post-merge via `ios-regression.yml` — that is the gate.
- If a task touches `Core.swift`, `MacrosImplementation/`, or `SyncableMacro.swift`, note in
  the plan that the iOS regression will run on merge.
