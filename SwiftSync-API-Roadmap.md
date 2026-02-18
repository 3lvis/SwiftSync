# SwiftSync API Proposal and Roadmap

Lean roadmap focused on shipping inbound sync first.

## Scope

- Deliver a stable, minimal sync API.
- Defer outbound export until later phase.

## Public API (current)

```swift
public enum SwiftSync {}

public extension SwiftSync {
  static func sync<Model: SyncUpdatableModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    options: SyncOptions = .init()
  ) async throws
}

public extension ModelContext {
  func sync<Model: SyncUpdatableModel>(
    _ payload: [Any],
    as model: Model.Type,
    options: SyncOptions = .init()
  ) async throws
}
```

## Core Types (current)

```swift
public struct SyncOptions: Sendable {
  public var deleteScope: DeleteScope
  public var dryRun: Bool
  public var batchSize: Int
  public var checkpoint: SyncCheckpoint?
}

public protocol SyncUpdatableModel: SyncModel {
  static func make(from payload: SyncPayload) throws -> Self
  func apply(_ payload: SyncPayload) throws -> Bool
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
- Real source-of-truth diff sync for common flat models

Included:
1. Identity mapping for `id` / `remoteID`
2. snake_case to camelCase mapping
3. Changed-value writes only
4. `SyncUpdatableModel` path for inserts/updates/deletes via payload diff

## Milestone 2: Relationship Basics

Shippable:
- Practical to-one/to-many sync support

Included:
1. Relationship application hook via `SyncRelationshipUpdatableModel`
2. Source-of-truth replacement semantics for relationship payloads

## Milestone 3: Hardening

Shippable:
- Additional safety and performance validation after real usage feedback

## Milestone 4 (Later / Last): Outbound Export

Shippable:
- Export API and outbound queue semantics

Only start this phase after Milestones 1-3 are stable in real app usage. This phase will cover syncing locally-created data from app to backend.

## Guardrails Against Over-Engineering

1. No new public API without a concrete use case.
2. No new module unless at least two call sites need it.
3. Keep runtime entry point as `sync` until outbound phase.
4. Prefer removing unused options over adding new ones.
