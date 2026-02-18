# SwiftSync API Proposal and Roadmap

Lean roadmap focused on shipping inbound sync first.

## Scope

- Deliver a stable, minimal sync API.
- Defer outbound export until later phase.

## Public API (current)

```swift
public enum SwiftSync {}

public extension SwiftSync {
  static func sync<Model: PersistentModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    options: SyncOptions = .init()
  ) async throws
}

public extension ModelContext {
  func sync<Model: PersistentModel>(
    _ payload: [Any],
    as model: Model.Type,
    options: SyncOptions = .init()
  ) async throws
}
```

## Core Types (current)

```swift
public enum SyncMode: Sendable {
  case upsertOnly
  case fullReplace
  case insertOnly
  case updateOnly
  case custom(insert: Bool, update: Bool, delete: Bool)
}

public struct SyncOptions: Sendable {
  public var mode: SyncMode
  public var relationshipMode: RelationshipMode
  public var conflictPolicy: ConflictPolicy
  public var deleteScope: DeleteScope
  public var dryRun: Bool
  public var batchSize: Int
  public var checkpoint: SyncCheckpoint?
}
```

## Error Model

`sync` succeeds or throws `SyncError`.

## Milestones

## Milestone 0: Foundation Slice

Shippable:
- Buildable package
- Demo scaffold
- No-op `sync` stub
- CI + tests

## Milestone 1: Happy Path Inbound Sync

Shippable:
- Real upsert sync for common flat models

Included:
1. Identity mapping for `id` / `remoteID`
2. snake_case to camelCase mapping
3. Changed-value writes only

## Milestone 2: Safe Replace

Shippable:
- `fullReplace` with scoped delete safety

Included:
1. `SyncMode.fullReplace`
2. `DeleteScope` enforcement

## Milestone 3: Relationship Basics

Shippable:
- Practical to-one/to-many sync support

## Milestone 4 (Later): Outbound Export

Shippable:
- Export API and outbound queue semantics

Only start this phase after Milestones 1-3 are stable in real app usage.

## Guardrails Against Over-Engineering

1. No new public API without a concrete use case.
2. No new module unless at least two call sites need it.
3. Keep runtime entry point as `sync` until outbound phase.
4. Prefer removing unused options over adding new ones.
