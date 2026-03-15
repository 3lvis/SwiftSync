import Foundation

public enum ScopeLoadPath: Sendable, Equatable, CaseIterable {
    case localFirstRefresh
    case networkFirst
}

public enum ScopeSyncPhase: Sendable, Equatable {
    case idle
    case loading
    case refreshing
    case failed
}

public struct ScopeSyncStatus: Sendable, Equatable {
    public let phase: ScopeSyncPhase
    public let path: ScopeLoadPath
    public let errorMessage: String?
    public let updatedAt: Date

    public init(phase: ScopeSyncPhase, path: ScopeLoadPath, errorMessage: String?, updatedAt: Date) {
        self.phase = phase
        self.path = path
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

public enum ScopeSyncStatusReducer {
    public static func start(path: ScopeLoadPath, now: Date = Date()) -> ScopeSyncStatus {
        ScopeSyncStatus(
            phase: path == .localFirstRefresh ? .refreshing : .loading,
            path: path,
            errorMessage: nil,
            updatedAt: now
        )
    }

    public static func succeed(previous: ScopeSyncStatus, now: Date = Date()) -> ScopeSyncStatus {
        ScopeSyncStatus(
            phase: .idle,
            path: previous.path,
            errorMessage: nil,
            updatedAt: now
        )
    }

    public static func fail(previous: ScopeSyncStatus, errorMessage: String, now: Date = Date()) -> ScopeSyncStatus {
        ScopeSyncStatus(
            phase: .failed,
            path: previous.path,
            errorMessage: errorMessage,
            updatedAt: now
        )
    }
}
