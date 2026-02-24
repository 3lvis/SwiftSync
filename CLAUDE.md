# CLAUDE.md

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

## Commit Guidelines

- Do NOT add attribution footer to commits:
  ```
  🤖 Generated with [Claude Code](https://claude.com/claude-code)

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```
- Do NOT auto-commit changes. Wait for explicit user instruction to commit.
- Before every commit:
  - run `git status --short`
  - confirm only intended files are staged
  - then run the commit command (sequentially)

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
