# Monolith-Friendly Simplification Pass

---

## Open items

- [ ] Align on a `strict` vs `monolith-demo` runtime profile and choose the default profile for Demo targets.
- [ ] Simplify key-style handling to snake_case-only in Demo paths while keeping library compatibility strategy explicit.
- [ ] Reduce date parsing surface area to one canonical inbound format for Demo backend payloads.
- [ ] Decide whether `@SyncQuery` relationship inference failures should fail-soft in Demo UX instead of crashing.
- [ ] Simplify demo backend create/update validation by defaulting missing non-critical fields server-side.
- [ ] Make checklist parser/server timestamps authoritative and remove client timestamp validation burden.
- [ ] Document non-negotiable strictness rules that remain in both profiles.
- [ ] Add profile-focused tests that assert relaxed Demo behavior without regressing core data integrity.

---

## Goal

Define a repo-wide simplification plan for a monolith-owned system (Demo app + Demo backend + SwiftSync runtime) where the same team controls both producer and consumer contracts.

The intent is to reduce avoidable complexity and friction while preserving guardrails that prevent real data corruption.

---

## Mental model

- Prefer one convention over multi-mode flexibility when only one stack is in use.
- Keep strictness where it protects integrity (scope boundaries, race safety, explicit clear semantics).
- Relax strictness that mainly protects unknown third-party clients.
- Optimize for fast iteration, easy debugging, and low cognitive load in Demo flows.

---

## Non-negotiable strictness (keep as-is)

These rules should remain strict even in monolith-demo profile:

1) **Missing vs null semantics**
- Keep `absent key => ignore` and `explicit null => clear`.
- Source: `docs/project/backend-contract.md`.

2) **Parent-scope-safe deletes**
- Keep scoped delete behavior so one parent sync never removes another parent's rows.
- Source: `SwiftSync/Sources/SwiftSync/API.swift` (parent-scoped sync paths).

3) **Serialized sync execution per container**
- Keep sync lease serialization to avoid write races.
- Source: `SwiftSync/Sources/SwiftSync/API.swift`.

4) **Many-to-many inverse anchor schema guardrail**
- Keep runtime schema validation requiring one explicit inverse anchor for many-to-many pairs.
- Source: `SwiftSync/Sources/SwiftSync/SyncContainer.swift`.

5) **Transactional backend writes**
- Keep transactional create/update sequences in Demo backend.
- Source: `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`.

---

## Repo-wide simplification opportunities

### A) Key-style simplification (Low risk)

Observation:
- Core library supports both `.snakeCase` and `.camelCase`, increasing branching and test surface.

Monolith-friendly option:
- Standardize Demo runtime and payloads on snake_case only.
- Keep library support documented, but avoid using dual-mode in Demo paths.

Primary files:
- `SwiftSync/Sources/SwiftSync/Core.swift`
- `Demo/Demo/App/DemoRuntime.swift`

### B) Date parsing simplification (Medium risk)

Observation:
- Date parser accepts many variants and coercions.

Monolith-friendly option:
- For Demo backend payloads, accept one canonical format (RFC3339/ISO8601 with timezone) and generate that format everywhere.

Primary files:
- `SwiftSync/Sources/SwiftSync/SyncDateParser.swift`
- `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`

### C) `@SyncQuery` inference failure behavior (Low risk)

Observation:
- Ambiguous/missing relationship inference can crash via precondition failure.

Monolith-friendly option:
- Demo profile fail-soft behavior: empty result + warning log + explicit guidance to pass `through:`.

Primary files:
- `SwiftSync/Sources/SwiftSync/ReactiveQuery.swift`

### D) Parent/relationship inference strict throws (High risk)

Observation:
- Sync inference throws when no candidate or multiple candidates exist.

Monolith-friendly option:
- Keep strict in library profile; consider optional Demo override only if needed, with loud diagnostics.

Primary files:
- `SwiftSync/Sources/SwiftSync/API.swift`

### E) Demo backend body validation breadth (Medium risk)

Observation:
- Demo create/update endpoints require many explicit fields and exact shapes.

Monolith-friendly option:
- Server-fill defaults for non-critical fields in Demo mode (`id`, timestamps, default state when omitted).

Primary files:
- `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`

### F) Checklist parser/timestamps permissiveness (Low risk)

Observation:
- Checklist parsing still validates client-provided timestamp fields and strict integer position type.

Monolith-friendly option:
- Make server timestamps authoritative and normalize positions by array order when missing.

Primary files:
- `DemoBackend/Sources/DemoBackend/DemoServerSimulator.swift`

### G) Sync helper API surface reduction (Medium risk)

Observation:
- Several helper overloads exist for non-syncable relation cases and silently no-op.

Monolith-friendly option:
- Reduce overload surface where possible and favor explicit syncable-related constraints in Demo code paths.

Primary files:
- `SwiftSync/Sources/SwiftSync/Core.swift`

### H) Startup recovery complexity (Medium risk)

Observation:
- Container initialization has ObjC-exception capture and optional store reset retry paths.

Monolith-friendly option:
- Demo runtime can use simpler recovery behavior (e.g. recreate local store) while preserving strict mode in library.

Primary files:
- `SwiftSync/Sources/SwiftSync/SyncContainer.swift`
- `Demo/Demo/App/DemoRuntime.swift`

---

## Phased rollout

Phase 1 (safe / low risk)
- Snake_case-only usage in Demo runtime.
- Checklist parser simplification and timestamp ownership.
- Fail-soft `@SyncQuery` diagnostics for Demo views.

Phase 2 (medium risk)
- Date format narrowing.
- Demo backend defaulting of non-critical create/update fields.
- Startup recovery simplification in Demo runtime.

Phase 3 (high risk / optional)
- Relationship inference fallback behavior in sync API (only with explicit profile gating and tests).

---

## Success criteria

- Lower code path count for Demo behavior (fewer branches/shape variants).
- Faster iteration with fewer non-actionable validation failures.
- No regressions in scope safety, relationship integrity, or sync race protection.
- Clear documentation of what is strict everywhere vs relaxed in monolith-demo profile.
