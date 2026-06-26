import Foundation
import Observation

/// The lifecycle of the sync that backs a synced read.
public enum SyncLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)

    /// The failure message, if this phase is `.failed`.
    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Drives one load action through the phases. Shared by the synced publishers so the load logic lives in
/// exactly one place.
@MainActor
@Observable
final class SyncLoadDriver {
    @ObservationIgnored private let action: @MainActor () async throws -> Void
    @ObservationIgnored private let fallbackMessage: String
    private(set) var phase: SyncLoadPhase = .idle

    init(fallbackMessage: String, _ action: @escaping @MainActor () async throws -> Void) {
        self.fallbackMessage = fallbackMessage
        self.action = action
    }

    func load() async {
        switch phase {
        case .loading, .loaded: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            try await action()
            phase = .loaded
        } catch {
            let described = (error as? LocalizedError)?.errorDescription?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (described?.isEmpty == false ? described : nil) ?? fallbackMessage
            phase = .failed(message: message)
        }
    }
}
