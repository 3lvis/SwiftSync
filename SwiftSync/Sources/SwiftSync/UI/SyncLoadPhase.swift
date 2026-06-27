import Foundation
import Observation

public enum SyncLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)

    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

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
