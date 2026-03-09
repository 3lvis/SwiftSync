# Sendable Playbook

## Goals

- Catch data-race risks early with compiler checks.
- Keep `@unchecked Sendable` as a narrow, documented escape hatch.
- Prefer actor isolation and value semantics over annotation-heavy suppression.

## Rules

- Add `Sendable` to value types that are intentionally transferred across concurrency domains.
- Use `@Sendable` for escaping closures executed in async tasks or concurrent contexts.
- Prefer `@MainActor` or actor ownership for mutable UI state.
- Avoid global mutable state; when unavoidable, isolate and document access.
- Do not add `@unchecked Sendable` without a safety invariant comment near the declaration.

## `@unchecked Sendable` Checklist

When `@unchecked Sendable` is required, verify all of the following:

- Mutations are serialized (single actor/queue or explicit lock).
- Public API does not expose unsynchronized mutable references.
- Lifetime/teardown paths are deterministic.
- A test exercises cross-task usage and teardown behavior.

## Package Settings

- `SwiftSync` package uses Swift 6 language mode and strict concurrency compiler flags.
- `DemoBackend` package uses Swift 6 language mode and strict concurrency compiler flags.
- `DemoCore` package uses Swift 6 language mode and strict concurrency compiler flags.

## Current direction

- Prefer `SyncPayloadConvertible` wrappers for typed payload boundaries.
- Avoid introducing new raw `[String: Any]` payload surfaces when a typed Sendable wrapper is possible.
