# Relationship Integrity (SwiftData + SwiftSync)

This document explains:

- why the Demo `Task.tags` bug happened
- why explicit relationship inverses matter for SwiftSync users
- why SwiftSync now warns on missing to-many inverses in `@Syncable`
- why `@Syncable(allowMissingToManyInverses: [...])` exists
- how to think about the SwiftData circular macro edge case

The goal is a simple mental model, not just implementation detail.

## Short Version

Use this rule:

- to-many relationships should have an explicit inverse (`@Relationship(inverse: ...)`)

Why:

- SwiftSync can correctly sync IDs into relationships
- but SwiftData still owns the local object graph / inverse relationship behavior
- implicit inverse inference can produce broken membership behavior in real sync flows

Exception:

- if SwiftData fails to compile when both sides are explicitly annotated (a circular macro expansion edge case), keep one explicit side and document the exception with:
  - `@Syncable(allowMissingToManyInverses: ["propertyName"])`

This keeps the exception visible and intentional.

## Mental Model

## 1) SwiftSync syncs membership intent, SwiftData owns the graph

Think of SwiftSync as saying:

- "Task `task-6` should be related to tags `[tag-12, tag-3]`"

SwiftData then materializes and maintains the object graph:

- `task.tags`
- `tag.tasks` (inverse)

If inverse relationships are ambiguous or inferred incorrectly, SwiftSync can do the "right" ID sync and still end up with a wrong in-memory/local graph after SwiftData applies relationship updates.

## 2) To-many relationships are the risky ones

To-many relationships are where membership integrity problems usually show up:

- many-to-many (`Task.tags <-> Tag.tasks`)
- one-to-many (`Project.tasks <-> Task.project`)

Why they are riskier:

- they represent sets of links
- they are more likely to be rewritten during batch sync
- shared related rows (for example the same tag used by two tasks) amplify inverse inconsistencies

## 3) "Missing inverse" bugs look like sync corruption, but the root cause is model integrity

Symptom:

- backend response is correct
- immediate targeted sync looks correct
- a later batch sync causes one relationship membership to disappear

That feels like a sync race, but the root issue can be an implicit/inferred inverse relationship in the model schema.

## The Demo `Task.tags` Bug (What Happened)

We hit a real bug in Demo while editing task tags.

Observed behavior:

1. Open "Edit Tags" for a task
2. Add tags and save
3. Save reports success
4. UI shows no change or partial change

What debugging showed:

- backend mutation succeeded
- backend returned the correct tag IDs
- targeted `syncTaskDetail` applied the correct tags locally
- later `syncProjectTasks` (batch task sync) caused one shared tag membership to drop

The specific pattern:

- a tag shared by multiple tasks disappeared from one task after the batch sync
- a unique tag remained

That strongly pointed to a local inverse relationship integrity problem, not a backend mutation problem.

Root cause:

- `Tag.tasks` did not have an explicit inverse to `Task.tags`
- SwiftData inverse behavior for that many-to-many pair was inferred/implicit
- batch sync of multiple tasks with shared tags caused local membership corruption

Fix:

- make the inverse explicit on the `Tag` side:

```swift
@Relationship(inverse: \Task.tags)
var tasks: [Task]
```

After that, the tag replacement flow behaved correctly.

## Why `@Syncable` Now Warns on Missing To-Many Inverses

SwiftSync can prevent a lot of user pain by warning early.

The `@Syncable` macro now emits a warning for to-many relationships that do not declare an explicit inverse.

Mental model:

- `@Syncable` is not only about payload mapping
- it is also a guardrail for model shapes that are risky in sync-heavy apps

This warning exists because the bug class is:

- hard to spot in code review
- hard to debug from UI symptoms
- costly to diagnose after the app grows

## Why This Is a Warning (Not Always an Error)

We initially tried stricter enforcement, but SwiftData has a compiler/macro edge case:

- annotating both sides of some relationships with explicit `@Relationship(inverse: ...)`
- can trigger a SwiftData circular macro expansion compiler error

Important clarification:

- this is a compiler/macro expansion issue
- not a runtime object-graph cycle issue

So SwiftSync cannot safely require "both sides explicit, always" in all cases.

## The Circular Macro Expansion Edge Case

In some schemas (especially many-to-many pairs), SwiftData can fail to compile when both sides are explicitly annotated.

Example pattern that may fail:

- `Tag.tasks` has `@Relationship(inverse: \Task.tags)`
- `Task.tags` also has `@Relationship(inverse: \Tag.tasks)`

This can produce a compiler error about circular macro expansion / circular reference.

Because of that, the practical rule becomes:

- prefer explicit inverses
- but if SwiftData compiler fails on the reciprocal annotation, keep one explicit side and document the exception

## Why `@Syncable(allowMissingToManyInverses: [...])` Is Needed

This is the explicit exception mechanism for the SwiftData edge case.

Example:

```swift
@Syncable(allowMissingToManyInverses: ["tags", "watchers"])
@Model
final class Task {
    var tags: [Tag]
    var watchers: [User]
}
```

What it means:

- "We know these to-many properties are missing a local explicit inverse annotation"
- "This is intentional"
- "Do not warn for these specific properties"

Why this is better than ignoring warnings:

- exceptions are local and explicit
- reviewers can see the exact properties being exempted
- the guardrail still applies to all other to-many relationships
- we keep pressure toward explicit inverses without blocking valid builds

## What `allowMissingToManyInverses` Is Not

It is not:

- a runtime fix
- a sync behavior flag
- a replacement for proper inverse modeling

It only suppresses a macro diagnostic for named properties.

You should use it only when:

- the reciprocal side already declares the inverse, and
- adding the local explicit inverse causes the SwiftData compiler circular macro error

## Practical Rules (Recommended)

## Default rule

For `@Syncable` models:

- declare explicit inverses for to-many relationships

## If SwiftData compiler fails when both sides are explicit

1. Keep one side explicitly annotated (the side that compiles and clearly documents the relationship)
2. Add `allowMissingToManyInverses` for the reciprocal to-many property
3. Add a short code comment if the relationship is non-obvious

## For critical many-to-many relationships

- add a regression test that exercises shared-membership batch sync behavior

This is exactly what we did for the tag corruption bug class.

## What We Added in SwiftSync to Prevent This Pain Again

## 1) Regression tests for the bug class

We added a standalone regression file that shows:

- missing explicit inverse can corrupt shared membership during batch sync (expected failure pin)
- explicit inverse preserves membership (passing control)

This makes the bug class visible and reproducible.

## 2) `@Syncable` diagnostic guardrail

The macro warns on missing to-many inverses by default.

This catches risky model shapes earlier than runtime debugging.

## 3) Explicit exception mechanism

`allowMissingToManyInverses` documents known-safe exceptions caused by SwiftData compiler limitations.

This prevents "warning fatigue" while keeping the policy strict by default.

## FAQ-Style Clarifications

## "If one side is explicit, why warn on the other side at all?"

Because the macro only has limited source/context visibility and cannot reliably prove reciprocal correctness in all cases.

A warning-by-default plus explicit allowlist is safer and more honest than silently guessing.

## "Does this mean SwiftSync is broken?"

No. The root issue is at the SwiftData relationship modeling/inverse layer.

SwiftSync can still:

- expose the risk
- provide guardrails
- provide tests
- document exceptions explicitly

## "Will this go away later?"

Possibly.

If SwiftData compiler behavior improves (or SwiftSync adds a stronger runtime schema validator), we can tighten the rule further and reduce exceptions.

## Recommended Next Hardening Step

Add a runtime schema validator (Debug/Test fail-fast) that checks:

- missing/implicit to-many inverses
- reciprocal mismatch diagnostics
- related model registration in `SyncContainer`

This complements the macro warning:

- macro = source-level guardrail
- runtime validator = cross-model/configuration guardrail

