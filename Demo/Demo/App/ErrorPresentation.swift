import Combine
import Foundation

enum ScreenLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(ErrorPresentationState)
}

extension ScreenLoadState {
    var isLoading: Bool {
        self == .loading
    }

    var errorPresentation: ErrorPresentationState? {
        guard case .error(let presentation) = self else { return nil }
        return presentation
    }
}

struct ErrorPresentationState: Equatable {
    let message: String
    let retryActionTitle: String?
}

func presentError(
    _ error: Error,
    retryActionTitle: String? = "Retry",
    fallbackMessage: String = "Something went wrong. Please try again."
) -> ErrorPresentationState {
    let localized = (error as? LocalizedError)?.errorDescription
    let trimmed = localized?.trimmingCharacters(in: .whitespacesAndNewlines)
    let message = (trimmed?.isEmpty == false ? trimmed : nil) ?? fallbackMessage
    return ErrorPresentationState(message: message, retryActionTitle: retryActionTitle)
}

enum ScreenLoadEvent {
    case onAppear
    case retry
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

        case .retry:
            guard case .error = state else { return (state, nil) }
            return (.loading, .load)

        case .loadSucceeded:
            return (.loaded, nil)

        case .loadFailed(let error):
            return (.error(presentFailure(error)), nil)

        }
    }
}

@MainActor
final class ScreenLoadMachine: ObservableObject {
    @Published private(set) var state: ScreenLoadState = .idle

    private let presentFailure: (Error) -> ErrorPresentationState

    init(presentFailure: @escaping (Error) -> ErrorPresentationState) {
        self.presentFailure = presentFailure
    }

    func send(_ event: ScreenLoadEvent) {
        let next = ScreenLoadReducer.reduce(state: state, event: event, presentFailure: presentFailure)
        state = next.0
    }

    func send(_ event: ScreenLoadEvent, run operation: @escaping () async throws -> Void) {
        let next = ScreenLoadReducer.reduce(state: state, event: event, presentFailure: presentFailure)
        state = next.0
        guard next.1 == .load else { return }

        Task { [weak self] in
            do {
                try await operation()
                await MainActor.run {
                    self?.send(.loadSucceeded)
                }
            } catch {
                await MainActor.run {
                    self?.send(.loadFailed(error))
                }
            }
        }
    }
}

enum SubmissionEvent {
    case submit
    case success
    case failure(Error)
    case dismissError
}

enum SubmissionState: Equatable {
    case idle
    case submitting
    case failed(ErrorPresentationState)
}

@MainActor
final class SubmissionMachine: ObservableObject {
    @Published private(set) var state: SubmissionState = .idle

    private let presentFailure: (Error) -> ErrorPresentationState

    init(presentFailure: @escaping (Error) -> ErrorPresentationState) {
        self.presentFailure = presentFailure
    }

    @discardableResult
    func send(_ event: SubmissionEvent) -> Bool {
        switch event {
        case .submit:
            guard state != .submitting else { return false }
            state = .submitting
            return true

        case .success:
            state = .idle
            return false

        case .failure(let error):
            state = .failed(presentFailure(error))
            return false

        case .dismissError:
            state = .idle
            return false
        }
    }
}
