import Foundation
import Observation

public enum SyncSubmissionPhase: Equatable, Sendable {
    case idle
    case submitting
    case failed(message: String)

    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// A submit while one is already in flight is ignored (the double-submit guard a screen otherwise
/// hand-wires); success returns to `.idle`, a throw becomes `.failed`. Plain-Swift and `@Observable`.
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

    public func dismissFailure() {
        if case .failed = phase { phase = .idle }
    }
}
