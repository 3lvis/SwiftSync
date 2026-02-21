# Parent Scope Follow-up

This document tracks what we removed now, and what still cannot be removed safely yet.

## Why This Exists

When you call:

```swift
try await container.sync(payload, as: LineItem.self, parent: order)
```

your expectation is correct: SwiftSync should sync `LineItem` rows for that `order`.

But parent sync has two jobs, not one:
1. Attach created/updated child rows to the parent.
2. Scope diff/delete to only that parent's children.

`parentRelationship` is the single typed key path that tells SwiftSync how to do both safely.

## Mental Model

Think of parent sync as:
1. "Which relationship field stores the parent on the child?"
2. "Which existing rows are inside this parent scope?"
3. "Apply upserts for payload rows."
4. "If `missingRowPolicy == .delete`, delete only missing rows from that same scope."

Without an explicit relationship key path, step 2 and step 4 can target the wrong rows.

## Minimal Usage Today

In many models, this is all you need:

```swift
extension Task: GlobalParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Task, Project?> { \.project }
}
```

What you do not need anymore in this common case:
- No `typealias SyncParent`.
- No explicit `syncIdentityPolicy` override.

## Real-World Scenarios

### Scenario A: E-commerce Order and Line Items

Models:
- Parent: `Order`
- Child: `LineItem`
- Relationship: `LineItem.order`

Sync call:

```swift
try await SwiftSync.sync(
  payload: [
    ["id": 1, "sku": "A-100", "qty": 2],
    ["id": 2, "sku": "B-200", "qty": 1]
  ],
  as: LineItem.self,
  in: context,
  parent: order123
)
```

What should happen:
1. Rows `1` and `2` are created/updated.
2. Each row gets `lineItem.order = order123`.
3. Delete pass (default `.delete`) only considers existing rows where `lineItem.order == order123`.
4. Rows for `order999` are untouched.

Why scoping matters:
- If scoped delete accidentally ran against all `LineItem` rows, syncing one order could wipe other orders.

### Scenario B: CRM Account and Contacts With Scoped Identity

Models:
- Parent: `Account`
- Child: `Contact`
- Identity is scoped (`.scopedByParent`)

Business rule:
- Different accounts may both have `contact.id = 10` from different external systems.

What scoped identity enables:
- `(accountA, id: 10)` and `(accountB, id: 10)` can coexist.
- Syncing account A does not rewrite or delete account B contact rows.

### Scenario C: Global Identity That Moves a Child

Models:
- Parent: `Warehouse`
- Child: `ProductLocation`
- Identity is global (`.global`)

Behavior:
1. Sync `id: 10` under warehouse A.
2. Later sync same `id: 10` under warehouse B.
3. Result is one row that now points to warehouse B.

Why this is valid:
- Global identity means "this child is unique across all parents."
- Parent sync still needs explicit parent relationship to perform the reassignment intentionally.

### Scenario D: Project Tasks With Ambiguous Relationships

Models:
- Parent: `Project`
- Child: `Task`
- Child has two references to `Project`:
- `task.project` (owner)
- `task.reviewProject` (secondary relation)

If SwiftSync guessed:
- It might attach using `reviewProject` instead of `project`.
- Scoped delete could then diff on `reviewProject` and delete wrong tasks.

Explicit declaration removes ambiguity:

```swift
extension Task: ParentScopedModel {
  static var parentRelationship: ReferenceWritableKeyPath<Task, Project?> { \.project }
}
```

### Scenario E: Restaurant Menus

Models:
- Parent: `Restaurant`
- Child: `MenuItem`

Daily sync payload for Restaurant A includes only today's active menu items.

Desired result:
- Remove stale items for Restaurant A.
- Keep Restaurant B menu untouched.

This only works safely if delete pass is strictly parent-scoped.

## Why Parent Object Alone Is Not Enough

`parent: someParent` gives SwiftSync the parent instance.
It does not tell SwiftSync which child property should be treated as "the parent link."

The system still needs:
- A writable key path to assign parent on create/update.
- The same key path to filter existing rows for scoped diff/delete.

That is exactly what `parentRelationship` provides.

## What Still Cannot Be Removed Safely

`parentRelationship` is still required because:
1. Parent assignment on insert/update must target a concrete property.
2. Scoped delete must filter by that exact property.
3. Multiple candidate relationships are common in real schemas.
4. Guessing wrong can cause cross-scope deletes (data loss risk).

## How Old Runtime Inference Worked (And Why We Avoid It)

Old behavior in Core Data style sync was often:
1. Find relationships to parent entity.
2. Pick first match.
3. Use it for attach + scoped delete.

Problems:
1. "First match" depends on model ordering.
2. Multiple matches are ambiguous.
3. Zero matches can silently degrade behavior.
4. Errors are discovered late, sometimes only after data corruption.

SwiftSync chooses deterministic typed configuration over guessing.

## Future Work

Potential safe inference path:
1. Infer only when exactly one candidate relationship exists.
2. Throw typed error for zero or multiple candidates.
3. Keep explicit `parentRelationship` as an override escape hatch.

## Goal

Convention-first ergonomics for simple models, explicit configuration for ambiguous models, and no silent cross-parent deletes.
