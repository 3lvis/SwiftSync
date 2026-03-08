# Manual `SyncUpdatableModel` Conformance (Advanced)

This page is intentionally advanced.

Use manual conformance when your sync path must transform incoming data during `make(from:)` / `apply(_:)` (normalization, derivation, guarded transitions), not just map keys.

`@Syncable` remains the default for convention-first models.

## High-value advanced use cases

- Canonicalization during ingest (trim, collapse whitespace, normalize case, sanitize placeholders).
- Field derivation (for example, generate `displayName` from multiple payload keys with precedence rules).
- Guarded updates (allow only valid state-machine transitions).
- Backward-compatible payload migration (old/new key coexistence with deterministic precedence).
- Selective mutation by trust metadata (ignore stale or low-confidence payload fragments).

## Lifecycle (`make` + `apply` + relationship pair)

`SwiftSync.sync(...)` uses this flow per payload row:

1. Resolve identity.
2. If no row exists, call `make(from:)` and insert.
3. If row exists, call `apply(_:)`.
4. Call `applyRelationships(_:in:operations:)`.

Method intent:

- `make(from:)` creates a new instance from payload data.
- `apply(_:)` updates scalar fields on an existing instance and returns whether anything changed.
- `applyRelationships(_:in:)` is the convenience relationship hook (default no-op).
- `applyRelationships(_:in:operations:)` is the operation-aware relationship hook; default behavior delegates to the 2-argument version.

## Why `SyncPayload` is public here

Manual conformances need stable payload access APIs while preserving strict sync semantics.

- `contains(_:)` checks presence (including key-style candidates), so partial payloads do not accidentally wipe fields.
- `value(for:as:)` reads optional/coercing values for tolerant transformations.
- `required(_:for:)` reads required/coercing values and throws `SyncError.invalidPayload` when a required value is unresolvable.

Contract semantics:

- Key absent -> ignore (no mutation).
- Key present as `null` -> clear/delete (when delete semantics apply).

## Advanced transformation example

```swift
import SwiftData
import SwiftSync

enum TicketStatus: String {
    case open
    case inProgress = "in_progress"
    case closed
}

@Model
final class Ticket {
    @Attribute(.unique) var id: Int
    var title: String
    var status: String
    var assigneeHandle: String?
    var assignee: User?
    var updatedAt: Date

    init(
        id: Int,
        title: String,
        status: String,
        assigneeHandle: String? = nil,
        assignee: User? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.assigneeHandle = assigneeHandle
        self.assignee = assignee
        self.updatedAt = updatedAt
    }
}

extension Ticket: SyncModelable {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<Ticket, Int> { \.id }
}

extension Ticket: SyncUpdatableModel {
    static func make(from payload: SyncPayload) throws -> Ticket {
        let rawTitle: String = try payload.required(String.self, for: "title")
        let canonicalTitle = normalizeTitle(rawTitle)

        let rawStatus: String = try payload.required(String.self, for: "status")
        let normalizedStatus = normalizeStatus(rawStatus)

        let normalizedHandle = payload.value(for: "assignee_handle", as: String.self)
            .map(normalizeHandle)

        return Ticket(
            id: try payload.required(Int.self, for: "id"),
            title: canonicalTitle,
            status: normalizedStatus.rawValue,
            assigneeHandle: normalizedHandle,
            updatedAt: payload.value(for: "updated_at", as: Date.self) ?? Date(timeIntervalSince1970: 0)
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false

        if payload.contains("title") {
            let incomingRaw: String = try payload.required(String.self, for: "title")
            let incoming = Self.normalizeTitle(incomingRaw)
            if title != incoming {
                title = incoming
                changed = true
            }
        }

        if payload.contains("status") {
            let incomingRaw: String = try payload.required(String.self, for: "status")
            let incoming = Self.normalizeStatus(incomingRaw)

            // Guarded transition: once closed, do not reopen from sync payload.
            if status == TicketStatus.closed.rawValue, incoming != .closed {
                throw SyncError.invalidPayload(
                    model: "Ticket",
                    reason: "Invalid status transition from closed to \(incoming.rawValue)"
                )
            }

            if status != incoming.rawValue {
                status = incoming.rawValue
                changed = true
            }
        }

        if payload.contains("assignee_handle") {
            let incoming = payload.value(for: "assignee_handle", as: String.self)
                .map(Self.normalizeHandle)
            if assigneeHandle != incoming {
                assigneeHandle = incoming
                changed = true
            }
        }

        if payload.contains("updated_at") {
            let incomingDate: Date = try payload.required(Date.self, for: "updated_at")
            if updatedAt != incomingDate {
                updatedAt = incomingDate
                changed = true
            }
        }

        return changed
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool {
        try syncApplyToOneForeignKey(
            self,
            relationship: \.assignee,
            payload: payload,
            keys: ["assignee_id", "owner_id"],
            in: context,
            operations: operations
        )
    }

    private static func normalizeTitle(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func normalizeHandle(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizeStatus(_ raw: String) -> TicketStatus {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "open", "todo":
            return .open
        case "in_progress", "inprogress", "doing":
            return .inProgress
        case "closed", "done", "resolved":
            return .closed
        default:
            return .open
        }
    }
}
```

## Advanced implementation rules

- Keep transforms deterministic and idempotent (same input -> same stored value).
- Keep `apply` presence-driven (`contains`) so partial payloads do not wipe fields accidentally.
- Put guarded business rules in `apply` (transition checks, stale-write protection, trust gates).
- Keep relationship mutation in `applyRelationships` and pass `operations` through so insert/update/delete policy remains effective.
- Prefer built-in relationship helpers (`syncApplyToOneForeignKey`, `syncApplyToManyForeignKeys`, `syncApplyToOneNestedObject`, `syncApplyToManyNestedObjects`) before custom graph mutation.
