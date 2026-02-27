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

- **Disk context** = what’s in the repo (persists via git)
- **RAM context** = the current working memory (gets lost if the agent stops or you switch machines)

RAM context is: what you tried, what failed, why choices were made, current hypotheses, key errors, and the exact next steps.

### Goal

Make work **restart-safe** by writing the agent’s RAM into the repo.

---

## Where it lives

Put all continuity files in **`.agents/`**:

- **`.agents/state.md`** — the current “brain snapshot” (source of truth)
- **`.agents/log.md`** — important commands + trimmed outputs (errors, failing tests)
- **`.agents/handoff.md`** — one paste-ready message to restart any agent

Keep these updated while working.

---

## 1) `.agents/state.md` (State Capsule)

**Purpose:** restore context in under a minute.

**Rules:**

- Keep it brief — facts over prose, but completeness beats an arbitrary line count
- Update whenever decisions change, you get blocked, or the plan shifts
- Facts > prose

**Template:**

```md
# State Capsule

## Goal

<one sentence>

## Current status

- ✅ Done:
- 🔄 In progress:
- ⛔ Blocked by:

## Decisions (don’t revisit)

- <decision> — <why>

## Constraints

- <must stay true>

## Key findings

- Tried: <x> → <result>
- Learned: <y>

## Next steps (exact)

1. <command/file/change>
2. ...

## Files touched

- path
- path
```

---

## 2) `.agents/log.md` (Transcript Delta)

**Purpose:** avoid re-discovering errors and important outputs.

**Rules:**

- Only high-signal snippets
- Always include the command that produced the output
- Trim aggressively; no walls of text

**Template:**

````md
# Transcript Delta

## <timestamp> <topic>

Command:

```bash
...
```

Output (trimmed):

```text
...
```

Notes:

- <why it matters>
````

---

## 3) `.agents/handoff.md` (Restart message)

**Purpose:** one message you can paste into a fresh agent and continue immediately.

**Rules:**

- Must fit in one message
- Must tell the agent to read `.agents/state.md` and `.agents/log.md` first
- Must specify the first 2–5 commands to run
- Must forbid re-litigating recorded decisions

**Template:**

```md
You are continuing work in this repo.

1. Read `.agents/state.md` and `.agents/log.md`.
2. Do NOT revisit anything under “Decisions (don’t revisit)”.
3. Start by running:

- <cmd>
- <cmd>
- <cmd> (optional)

Then execute “Next steps (exact)” from `.agents/state.md` in order.
If anything fails, append the command + trimmed output to `.agents/log.md`, then update `.agents/state.md`.
```

---

## Operating procedure

### Start (every agent run)

1. Read `.agents/state.md`
2. Read `.agents/log.md`
3. Execute `.agents/state.md -> Next steps (exact)`

### During work

- Decision made → update **Decisions** in `.agents/state.md`
- Meaningful error/output → append to `.agents/log.md`
- Keep **Next steps** accurate and ordered

### On stop (before ending or when nearing usage cap)

1. Update `.agents/state.md` so it reflects reality
2. Append the last meaningful outputs to `.agents/log.md`
3. Refresh `.agents/handoff.md` so it can be pasted into a new agent immediately

This is required specifically to survive:

- sudden stop due to **usage caps**
- switching between **home/work computers**

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
| Start feature branch | Create `.agents/` and begin state tracking |
| Switch machines mid-task | Read `.agents/` to restore context — no lost work |
| Usage cap hit mid-task | Read `.agents/` on resume — continue exactly where you left off |
| PR merged / branch closed | CI purges `.agents/` automatically on next push to `main` |
| Hard context switch (abandon task) | Delete `.agents/` — stale state misleads more than it helps |

### Why not gitignore it?

Gitignoring `.agents/` defeats the "switch machines" goal. The files must be committed to survive machine switches. The tradeoff is: commit freely on feature branches, CI cleans up on merge.
