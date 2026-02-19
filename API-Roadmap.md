# API Proposal and Roadmap

Lean roadmap focused on shipping deterministic sync and export.

## Scope

- Deliver a stable, minimal sync API.
- Deliver best-effort outbound export API with low configuration.

## Public API (current)

```swift
public enum SwiftSync {}

public extension SwiftSync {
  static func sync<Model: SyncUpdatableModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext
  ) async throws

  static func sync<Model: ParentScopedModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext,
    parent: Model.SyncParent
  ) async throws

  static func export<Model: ExportModel>(
    as model: Model.Type,
    in context: ModelContext,
    using options: ExportOptions = ExportOptions()
  ) throws -> [[String: Any]]

  static func export<Model: ExportModel & ParentScopedModel>(
    as model: Model.Type,
    in context: ModelContext,
    parent: Model.SyncParent,
    using options: ExportOptions = ExportOptions()
  ) throws -> [[String: Any]]
}
```

## Core Types (current)

```swift
public protocol SyncUpdatableModel: SyncModel {
  static func make(from payload: SyncPayload) throws -> Self
  func apply(_ payload: SyncPayload) throws -> Bool
}

public protocol ParentScopedModel: SyncUpdatableModel {
  associatedtype SyncParent: PersistentModel
  static var parentRelationship: ReferenceWritableKeyPath<Self, SyncParent?> { get }
}

public protocol ExportModel: SyncModel {
  func exportObject(using options: ExportOptions, state: inout ExportState) -> [String: Any]
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
3. Changed-value writes only (field-by-field comparison for matching identities)
4. `SyncUpdatableModel` path for inserts/updates/deletes via payload diff

## Milestone 2: Relationship Basics

Shippable:
- Practical to-one/to-many sync support

Included:
1. Relationship application hook via `SyncRelationshipUpdatableModel`
2. Source-of-truth replacement semantics for relationship payloads

## Milestone 3: Hardening Sync

## Milestone 4: Export

Shippable:
- Best-effort JSON export with deterministic ordering by identity

Included:
1. `SwiftSync.export` (global and parent-scoped)
2. Export options for key style / relationship mode / date formatting / nulls
3. Macro mapping controls: `@NotExport`, `@RemoteKey`, `@RemotePath`, `@PrimaryKey(remote:)`

## Guardrails Against Over-Engineering

1. No new public API without a concrete use case.
2. No new module unless at least two call sites need it.
3. Keep sync entry point as `sync` until outbound phase.
4. Prefer removing unused options over adding new ones.
