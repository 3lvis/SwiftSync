import Foundation

@MainActor
public final class FiniteAsyncRunner {
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let operation: @Sendable (Int) async -> Void
    private let onStop: @MainActor () async -> Void
    private var workerTask: _Concurrency.Task<Void, Never>?

    public private(set) var isRunning = false

    public init(
        sleep: @escaping @Sendable (UInt64) async throws -> Void,
        operation: @escaping @Sendable (Int) async -> Void,
        onStop: @escaping @MainActor () async -> Void
    ) {
        self.sleep = sleep
        self.operation = operation
        self.onStop = onStop
    }

    public func start(maxIterations: Int, intervalNanoseconds: UInt64) {
        guard !isRunning, maxIterations > 0 else { return }
        isRunning = true

        workerTask = _Concurrency.Task {
            defer {
                workerTask = nil
                isRunning = false
                _Concurrency.Task { await onStop() }
            }

            for iteration in 0..<maxIterations {
                guard !_Concurrency.Task.isCancelled else { break }

                async let run: Void = operation(iteration)
                do {
                    try await sleep(intervalNanoseconds)
                } catch {
                    break
                }
                _ = await run
            }
        }
    }

    public func stop() {
        workerTask?.cancel()
        workerTask = nil
        isRunning = false
        _Concurrency.Task { await onStop() }
    }
}
