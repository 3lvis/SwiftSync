# Relationship Integrity (SwiftData + SwiftSync)

This document captures the corrected rule learned from debugging the Demo tag bug.

## The Correct Rule

- This is a **many-to-many** issue.
- It is **not** a general "all to-many relationships need explicit inverses" issue.
- Regular to-many relationships (for example one-to-many) **work fine** without explicit inverses.
- For a **many-to-many** pair, you need **one explicit inverse anchor** (not two).
- Adding explicit inverse annotations on **both sides** can trigger a SwiftData compiler bug:
  - `"Circular reference resolving attached macro 'Relationship'"`

## Very Simple Mental Model

In a many-to-many pair, SwiftData has to maintain the same links from two directions:

- `Task.tags`
- `Tag.tasks`

If neither side explicitly declares the inverse, SwiftData has to infer/guess how the pair maps.

That inference can break under batch updates (especially when relationships are shared, like one tag used by multiple tasks).

Adding **one explicit inverse anchor** tells SwiftData:

- "These two properties are the same relationship. Use this mapping."

That removes the guess and fixes the broken membership updates.

## What We Verified in Demo (Experiments)

### 1) Tag bug fix worked with one explicit inverse on `Tag`

This fixed the bug:

```swift
@Relationship(inverse: \Task.tags)
var tasks: [Task]
```

### 2) Tag bug fix also worked with one explicit inverse on `Task`

This also fixed the bug:

```swift
@Relationship(inverse: \Tag.tasks)
var tags: [Tag]
```

Conclusion:

- the `Task.tags <-> Tag.tasks` many-to-many pair needed **one explicit inverse anchor**
- it did **not** require explicit inverses on both sides

### 3) Regular to-many relationships still worked without explicit inverses

As a verification step, explicit inverses were removed from:

- `User.assignedTasks`
- `User.reviewTasks`

Those relationships still worked fine.

Conclusion:

- this bug pattern is not "all to-many relationships"
- it is specifically about the problematic many-to-many pair with no inverse anchor

## Why the Demo `tags` Pair Broke but `watchers` Did Not

Demo has two many-to-many pairs:

1. `Task.tags <-> Tag.tasks`
2. `Task.watchers <-> User.watchedTasks`

Before the fix:

- `Task.tags <-> Tag.tasks` had **no explicit inverse on either side** (zero anchors) -> this is the one that broke
- `Task.watchers <-> User.watchedTasks` already had an explicit inverse anchor on `User.watchedTasks` -> this one worked

So the key condition was:

- **many-to-many with zero explicit inverse anchors**

## Practical Rule for SwiftSync + SwiftData Models

Use this rule in app models:

### Many-to-many

- Ensure the pair has **at least one** explicit inverse annotation.
- Do **not** force both sides if SwiftData hits the circular macro compiler error.

### One-to-many

- Explicit inverse is optional for correctness in the bug pattern we observed.
- You can still add one for clarity if it compiles cleanly.

## What To Avoid

Avoid this in many-to-many pairs:

- neither side has `@Relationship(inverse: ...)`

That is the exact configuration that produced the Demo tag membership corruption during batch sync.

## SwiftData Compiler Edge Case (Important)

Trying to annotate both sides of a many-to-many pair can fail with:

- `"Circular reference resolving attached macro 'Relationship'"`

This means:

- "add explicit inverses everywhere on both sides" is not a workable rule
- the correct practical approach is one explicit inverse anchor for the pair

## Why There Is No Broad `@Syncable` Inverse Warning

We previously added an `@Syncable` warning for all missing to-many inverses.

That rule was too broad and produced the wrong guidance (including for one-to-many relationships that work fine), so it was removed.

If we add guardrails again, they should target the real risk:

- many-to-many pairs with zero explicit inverse anchors

That likely belongs in a runtime schema validator (cross-model validation), not a broad local macro warning.

## Recommended Team Wording (copy/paste)

- Many-to-many relationships should have **one explicit inverse anchor**.
- One-to-many relationships work fine without explicit inverses.
- Do not annotate both sides of a many-to-many pair if SwiftData throws the circular `@Relationship` macro error.
