import Foundation

/// The single error currency for SwiftSync: every SwiftSync operation that can fail throws one of
/// these, so a consumer catches one type. (Per-operation push *rejections* are partial-success data,
/// reported as `SyncPendingChangesFailure` in the response rather than thrown — see `withPendingChanges`.)
public enum SyncError: Error, Sendable, Equatable {
    case invalidPayload(model: String, reason: String)
    case cancelled
    case schemaValidation(reason: String)
    case containerInitialization(reason: String)
}

extension SyncError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let model, let reason):
            return "Invalid payload for \(model): \(reason)"
        case .cancelled:
            return "Sync was cancelled."
        case .schemaValidation(let reason):
            return reason
        case .containerInitialization(let reason):
            return reason
        }
    }
}
