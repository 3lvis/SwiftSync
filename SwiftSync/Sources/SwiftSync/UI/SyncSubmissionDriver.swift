import Foundation
import Observation

/// The lifecycle of a one-shot submission (save, delete, send) — the write-side counterpart of
/// `SyncLoadPhase`.
public enum SyncSubmissionPhase: Equatable, Sendable {
    case idle
    case submitting
    case failed(message: String)

    /// The failure message, if this phase is `.failed`.
    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Runs a single in-flight submission through its phases. A submit while one is already in flight is
/// ignored (the double-submit guard a screen otherwise hand-wires); success returns to `.idle`, a throw
/// becomes `.failed`. Plain-Swift and `@Observable`, the write-side counterpart of the synced read drivers.
@MainActor
@Observable
public final class SyncSubmissionDriver {
    @ObservationIgnored private let fallbackMessage: String
    public private(set) var phase: SyncSubmissionPhase = .idle

    public init(fallbackMessage: String = "Something went wrong. Please try again.") {
        self.fallbackMessage = fallbackMessage
    }

    public func submit(_ action: @MainActor () async throws -> Void) async {
        guard phase != .submitting else { return }
        phase = .submitting
        do {
            try await action()
            phase = .idle
        } catch {
            let described = (error as? LocalizedError)?.errorDescription?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (described?.isEmpty == false ? described : nil) ?? fallbackMessage
            phase = .failed(message: message)
        }
    }

    /// Clear a `.failed` phase back to `.idle` (e.g. the user dismissed the error). A no-op otherwise.
    public func dismissFailure() {
        if case .failed = phase { phase = .idle }
    }
}
