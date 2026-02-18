# SwiftSync

A minimal SwiftData sync framework.

## Status

- Proposed
- Audience: iOS engineers
- Current scope: inbound sync only (`server -> local`)
- Deferred: outbound export (`local -> server`)

## Goal

Ship a reliable `sync` API first.

## Non-Goals (for now)

- No networking layer.
- No outbound queue/reconciliation.
- No agent-specific APIs.
- No broad compatibility/migration framework.
- No performance hardening work until core behavior is stable.

## Minimal Public API

```swift
public enum SwiftSync {}

public extension SwiftSync {
  static func sync<Model: SyncUpdatableModel>(
    payload: [Any],
    as model: Model.Type,
    in context: ModelContext
  ) async throws
}
```

## Model Contract (Milestone 1)

Models participating in sync conform to `SyncUpdatableModel`:

- declare identity key path
- provide `make(from:)` for inserts
- provide `apply(_:)` for updates (return `true` only if a value changed)

`SyncPayload` provides snake_case/camelCase lookup and `id`/`remoteID` identity key conventions.

For relationship updates, models can additionally conform to `SyncRelationshipUpdatableModel` and apply to-one/to-many changes during the same sync run.

## Principles

1. Keep API small.
2. Prefer convention over custom DSL when possible.
3. Add features only when a concrete use case requires them.
4. Make behavior deterministic.
5. Fail clearly with typed errors.

## Internal Direction (not public API)

- Parse payload
- Decide changes
- Apply changes in `ModelContext`

This can evolve internally without growing public surface area.

## Example

```swift
try await SwiftSync.sync(
  payload: usersPayload,
  as: User.self,
  in: modelContext
)
```

## Milestones

### Milestone 0: Foundation

- Buildable package
- Demo app scaffold
- Basic sync wiring
- Basic tests and CI

### Milestone 1: Inbound Happy Path

- snake_case -> camelCase mapping
- identity mapping (`id`, `remoteID`)
- source-of-truth diff behavior (insert/update/delete)
- write-on-change behavior

### Milestone 2: Relationships

- common to-one and to-many behavior
- `SyncRelationshipUpdatableModel` hook for relationship diff application

### Milestone 3: Hardening

- additional safety/performance validation in production scenarios

### Later (Last): Outbound Export

Add export only after inbound sync is stable in real usage. This is where locally-created data will be synced upstream (`local -> server`).
