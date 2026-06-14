import Foundation

enum ScopeLoadPath: Sendable, Equatable, CaseIterable {
    case localFirstRefresh
    case networkFirst
}

enum ScopeSyncPhase: Sendable, Equatable {
    case idle
    case loading
    case refreshing
    case failed
}

struct ScopeSyncStatus: Sendable, Equatable {
    let phase: ScopeSyncPhase
    let path: ScopeLoadPath
    let errorMessage: String?
    let updatedAt: Date

    init(phase: ScopeSyncPhase, path: ScopeLoadPath, errorMessage: String?, updatedAt: Date) {
        self.phase = phase
        self.path = path
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

enum ScopeSyncStatusReducer {
    static func start(path: ScopeLoadPath, now: Date = Date()) -> ScopeSyncStatus {
        ScopeSyncStatus(
            phase: path == .localFirstRefresh ? .refreshing : .loading,
            path: path,
            errorMessage: nil,
            updatedAt: now
        )
    }

    static func succeed(previous: ScopeSyncStatus, now: Date = Date()) -> ScopeSyncStatus {
        ScopeSyncStatus(
            phase: .idle,
            path: previous.path,
            errorMessage: nil,
            updatedAt: now
        )
    }

    static func fail(previous: ScopeSyncStatus, errorMessage: String, now: Date = Date()) -> ScopeSyncStatus {
        ScopeSyncStatus(
            phase: .failed,
            path: previous.path,
            errorMessage: errorMessage,
            updatedAt: now
        )
    }
}
