# Bug-Solving Playbook

This document defines the standard way to work when a real bug appears and the right fix is not yet known.

The method is:

- start from behavior, not theory
- locate the first wrong state
- prove the failing layer
- rebuild the cleanest fix from base
- merge the smallest verified solution

## Principles

- Do not fix from instinct.
- Do not argue from symptoms alone.
- Do not stop at the first workaround.
- Prefer the deepest correct fix, but only after proving the layer.
- Keep the final branch cleaner than the investigation.

## Phase 1: Establish the bug

Start with the real failure.

- Reproduce the bug in the actual user flow.
- State the expected result.
- State the actual result.
- Describe the bug in behavioral terms, not implementation guesses.

The first question is always:

- what should have changed, and what did not?

## Phase 2: Localize the failure

Map the state path from input to output.

Typical path:

- user action
- draft or transient state
- exported payload
- mutation/service layer
- backend response
- local persistence
- reactive publisher
- machine or view model
- rendered UI

The goal is to find the first wrong state.

If the value is correct all the way down and only the UI is stale, that is a different bug from a bad write or a bad payload.

## Phase 3: Instrument the path

Add diagnostics before changing behavior.

Diagnostics must be visible in the failing execution path.

Use transports the failing run can actually surface:

- assertion-attached trace output
- test-readable artifacts
- narrow test-only diagnostic seams

Do not rely on diagnostics that the failing run cannot read.

Improving diagnostic transport is often more important than improving log wording.

## Phase 4: Use the right execution loop

Use the strongest execution environment for the current question.

- use local automated runs when they give the best signal
- use Xcode when UI behavior is the question
- use user-assisted manual runs when they expose the right logs faster or more reliably

This is one debugging loop, not separate modes of work:

1. add narrow instrumentation
2. run one focused scenario
3. read the result
4. update the hypothesis

## Phase 5: Isolate the narrowest plausible layer

Try to reproduce the bug in the narrowest layer that could realistically own it.

That may be:

- a unit test
- a service or machine test
- a publisher or observation test
- an integration or UI test

Start narrow, but do not force the wrong layer.

A lower-level test that does not reproduce the bug is still useful evidence. It removes a layer from suspicion.

## Phase 6: Distinguish product bugs from test-surface bugs

A failing test does not always mean the product layer is wrong.

Two different failure classes exist:

- product bug: the user-visible state is wrong
- test-surface bug: the test is reading an unstable or incidental surface

Do not change production behavior to compensate for a weak test surface unless that surface is itself part of the product contract.

For UI tests, assert the most stable user-meaningful surface, not the most local surface.

## Phase 7: Work in investigation branches, not on the final branch

Investigation creates residue:

- temporary logging
- probe assertions
- discarded fixes
- experimental tests

Do that work on an investigation branch.

If a new bug is found while working on a base branch or integration branch:

1. stop
2. move the in-progress bug work onto a new investigation branch immediately
3. keep the base branch clean

Do not debug on the branch you are trying to keep mergeable.

Once the likely cause is known:

1. return to the clean base branch
2. create a fresh branch
3. rebuild only the proven fix

Do not trim a messy branch into shape if rebuilding from base is cheaper and clearer.

## Phase 8: Treat the first working fix as provisional

A first working fix is useful because it proves the symptom can be corrected.

It is not yet proof that the right layer was fixed.

After a working fix, ask:

- why did this fix work?
- should this fix live here?
- is this layer compensating for a deeper defect?

If the answer is unclear, continue the investigation.

## Phase 9: Use mechanism-level tests when state and reactivity diverge

Some bugs are not about wrong final state. They are about correct state failing to propagate.

When that happens, write tests that separate:

- the underlying value
- the observation or notification path

Spy tests are useful here because they show whether:

- state mutation succeeded
- dependents were notified

That distinction is often the difference between a real root cause and a misleading symptom.

## Phase 10: Reduce noise while preserving the contract

When a test is failing across multiple surfaces, reduce the assertion surface.

Keep only the assertions that prove the core user contract.

Do not keep fragile secondary assertions during localization if they hide the real signal.

Once the bug is understood, expand coverage again only if the added assertions protect a stable contract.

## Phase 11: Prefer the deeper fix when it is proven

If a lower layer is shown to be wrong, fix that layer.

A deeper fix is better when it:

- explains the bug mechanically
- removes an upper-layer workaround
- is protected by a focused regression test
- still keeps the user-facing regression test valuable

Do not keep a workaround in place once the real lower-layer defect is understood and fixed.

## Phase 12: Merge the clean solution

Before merging:

- keep the tests that prove the behavior
- keep the tests that prove the mechanism, when needed
- remove temporary diagnostics
- remove discarded probes and abandoned assertions
- remove superseded workaround code
- rerun focused verification on the clean branch

The merged diff should show:

- the problem
- the right fix
- the proof

## Required workflow

1. Reproduce the real bug.
2. Define expected vs actual behavior.
3. Map the state path across layers.
4. Add diagnostics the failing run can surface.
5. Run one focused scenario at a time.
6. Isolate the narrowest plausible layer.
7. Separate product defects from test-surface defects.
8. Move bug work onto an investigation branch immediately.
9. Once the likely cause is known, branch cleanly from base.
10. Rebuild only the proven fix.
11. Ask whether the fix belongs deeper.
12. Keep or add tests that prove both behavior and mechanism.
13. Remove temporary investigation residue.
14. Merge the clean, verified solution.
