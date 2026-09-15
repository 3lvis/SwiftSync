# Learnings

**What sessions keep running into, written for the next session that runs into it.** This is a reference,
searched by symptom, and that is the whole of its job. Lead with the symptom the next session will search
for, and write for them rather than for promotion — most entries stay here, and that is the point.

Graduating into [`AGENTS.md`](AGENTS.md) takes that document's own bar: a line earns its place there by
being live in almost every session, which recurrence alone leaves unanswered. Recurrence makes a lesson a
candidate; the citations below are what settle it.

## One lesson, one file

Everything lives in [`LEARNINGS/`](LEARNINGS/), a file per lesson, named for the minute you wrote it:

```
LEARNINGS/2026-09-15-1520-a-warm-build-hides-a-warning.md
```

The filename is the whole of the discipline. As many branches write this repository at once as there are
worktrees open, and a file apiece is what lets them: each branch adds a path the others lack, so a merge
takes every side whole and the file you wrote arrives byte for byte. Sharing one file costs a conflict per
pair of open branches, and `merge=union` in `.gitattributes` does not save you — it is read off a **working
tree**, which a server-side merge lacks, so it clears the conflicts on your machine and none of the ones
that block a merge button.

Inside:

- **Lead with the principle in bold**, then what it cost. One file, one lesson — a second lesson is a
  second file.
- **Keep the specifics that prove the recurrence** — the file, the count, the incident. Generalising
  happens at graduation; here, the detail is what lets the next session recognise the same thing again.
- **Close with a stamp on its own last line: `*— who, YYYY-MM-DD HH:MM*`.** The stamp is the count: the
  same name at two times means two sessions, and two names means two people, which is the stronger case for
  promoting it. A file that has been grouped carries one stamp per sighting.
- **Where another document reaches for it by name, the file says so.** That is a citation, recorded where
  the pass will find it.

## Leave the judging to the periodic pass

Whether somebody already wrote it, and whether it has earned a place in AGENTS, are each answered better
over the whole set than one entry at a time, and each asks you to hold a second job in your head while you
finish the first. So write the file, stamp it, and move on. Writing the same lesson twice is the intended
outcome: two files saying one thing is the evidence that it is a pattern rather than one bad afternoon.

## The periodic pass

Two signals drive it, and they measure different things. A **stamp** counts how often we hit a thing, which
is what writing produces. A **citation** counts how often it helped, which is what reading produces — and
that one lives in merged PR bodies, because the PR template asks every task for it:

```
gh pr list --state merged --limit 200 --json number,body \
  --jq '.[] | select(.body | test("Earned its keep")) | [.number, .body] | @tsv'
```

Every two months, one session walks the files against those citations:

1. **Group what repeats.** Several files saying one thing become one file **carrying every stamp**, since
   the stamps are the count and folding them into one throws that count away. The others go.
2. **Graduate what is cited widely** into [`AGENTS.md`](AGENTS.md) — cited by several tasks of different
   shapes — and delete the file once the rule carries everything it said. A lesson that recurs while every
   citation comes from one kind of branch stays a record here, behind the pointer.
3. **Prune what stayed unread.** A file that has sat through two passes — four months — still carrying its
   one stamp, uncited, goes. It was one afternoon rather than a pattern, and git keeps it either way.
4. **Demote an AGENTS line that goes two passes uncited** back to a file here. AGENTS earns its length by
   loading into every session, so a line every session reads past is costing all of them and serving one.
   This is the half that keeps the binding document short, and it is the reason a citation is worth the ten
   seconds it takes to write.

History lives in git, so a prune is reversible and a `git log --diff-filter=D -- LEARNINGS/` lists what has
gone.
