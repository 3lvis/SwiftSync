You are continuing work in this repo.

1. Read `.agents/state.md` and `.agents/log.md`.
2. Do NOT revisit anything under "Decisions (don't revisit)".
3. Start by running:

- `git log --oneline -5` (confirm current branch is `refactor/fold-export-model`)
- `gh run list --limit 3` (check latest CI status)
- `cat .github/workflows/ci.yml` (see current state of CI file)

Then execute "Next steps (exact)" from `.agents/state.md` in order.
If anything fails, append the command + trimmed output to `.agents/log.md`, then update `.agents/state.md`.
