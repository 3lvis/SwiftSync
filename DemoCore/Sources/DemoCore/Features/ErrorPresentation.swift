import Foundation
import Observation

public enum ScreenLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(ErrorPresentationState)
}

extension ScreenLoadState {
    public var isLoading: Bool {
        self == .loading
    }

    public var errorPresentation: ErrorPresentationState? {
        guard case .error(let presentation) = self else { return nil }
        return presentation
    }
}

public struct ErrorPresentationState: Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public func presentError(
    _ error: Error,
    fallbackMessage: String = "Something went wrong. Please try again."
) -> ErrorPresentationState {
    let localized = (error as? LocalizedError)?.errorDescription
    let trimmed = localized?.trimmingCharacters(in: .whitespacesAndNewlines)
    let message = (trimmed?.isEmpty == false ? trimmed : nil) ?? fallbackMessage
    return ErrorPresentationState(message: message)
}

public enum ScreenLoadEvent {
    case onAppear
    case loadSucceeded
    case loadFailed(Error)
}

private enum ScreenLoadEffect {
    case load
}

private enum ScreenLoadReducer {
    static func reduce(
        state: ScreenLoadState,
        event: ScreenLoadEvent,
        presentFailure: (Error) -> ErrorPresentationState
    ) -> (ScreenLoadState, ScreenLoadEffect?) {
        switch event {
        case .onAppear:
            guard state == .idle else { return (state, nil) }
            return (.loading, .load)

        case .loadSucceeded:
            return (.loaded, nil)

        case .loadFailed(let error):
            return (.error(presentFailure(error)), nil)

        }
    }
}

@MainActor
@Observable
public final class ScreenLoadMachine {
    public private(set) var state: ScreenLoadState = .idle

    private let presentFailure: (Error) -> ErrorPresentationState

    public init(presentFailure: @escaping (Error) -> ErrorPresentationState) {
        self.presentFailure = presentFailure
    }

    public func send(_ event: ScreenLoadEvent) {
        let next = ScreenLoadReducer.reduce(state: state, event: event, presentFailure: presentFailure)
        state = next.0
    }

    public func send(_ event: ScreenLoadEvent, run operation: @escaping @MainActor () async throws -> Void) {
        let next = ScreenLoadReducer.reduce(state: state, event: event, presentFailure: presentFailure)
        state = next.0
        guard next.1 == .load else { return }

        _Concurrency.Task { @MainActor [weak self] in
            do {
                try await operation()
                self?.send(.loadSucceeded)
            } catch {
                self?.send(.loadFailed(error))
            }
        }
    }
}
