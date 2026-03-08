import Foundation

enum ScreenLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(ErrorPresentationState)
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
