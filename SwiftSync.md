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

## Options We Keep

- `SyncMode` (`upsertOnly`, `fullReplace`, `insertOnly`, `updateOnly`, `custom`)
- `RelationshipMode`
- `ConflictPolicy`
- `DeleteScope`
- `batchSize`

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
  in: modelContext,
  options: .init(mode: .upsertOnly)
)
```

## Milestones

### Milestone 0: Foundation (current)

- Buildable package
- Demo app scaffold
- No-op sync stub
- Basic tests and CI

### Milestone 1: Inbound Happy Path

- snake_case -> camelCase mapping
- identity mapping (`id`, `remoteID`)
- real upsert behavior

### Milestone 2: Safe Replace

- `fullReplace`
- scoped deletes only

### Milestone 3: Relationships

- common to-one and to-many behavior

### Later: Outbound Export

Add export only after inbound sync is stable in real usage.
