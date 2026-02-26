# CLAUDE.md

@AGENTS.md

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
