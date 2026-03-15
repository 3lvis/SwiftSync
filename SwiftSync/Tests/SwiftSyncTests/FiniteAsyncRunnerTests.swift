import Foundation
import Testing
@testable import SwiftSync

@MainActor
struct FiniteAsyncRunnerTests {
    @Test("runner stays idle until start")
    func runnerStaysIdleUntilStart() async throws {
        let counter = IterationCounter()
        let runner = FiniteAsyncRunner(
            sleep: { _ in },
            operation: { _ in await counter.increment() },
            onStop: {}
        )

        #expect(runner.isRunning == false)
        try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        #expect(await counter.value == 0)
    }

    @Test("runner stops after max iterations")
    func runnerStopsAfterMaxIterations() async {
        let seen = IterationLog()
        let finished = LockedFlag()

        let runner = FiniteAsyncRunner(
            sleep: { _ in },
            operation: { iteration in await seen.append(iteration) },
            onStop: { await finished.set() }
        )

        runner.start(maxIterations: 3, intervalNanoseconds: 0)
        await waitForFlag(finished)

        #expect(runner.isRunning == false)
        #expect(await seen.values == [0, 1, 2])
    }

    @Test("runner stop cancels active session")
    func runnerStopCancelsActiveSession() async throws {
        let counter = IterationCounter()
        let runner = FiniteAsyncRunner(
            sleep: { _ in try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) },
            operation: { _ in await counter.increment() },
            onStop: {}
        )

        runner.start(maxIterations: 40, intervalNanoseconds: 1_000_000_000)
        try await _Concurrency.Task.sleep(nanoseconds: 30_000_000)
        runner.stop()
        try await _Concurrency.Task.sleep(nanoseconds: 30_000_000)

        #expect(runner.isRunning == false)
        #expect(await counter.value < 40)
    }

    private func waitForFlag(_ flag: LockedFlag, timeoutNanoseconds: UInt64 = 1_000_000_000) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while await !flag.value {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                Issue.record("Timed out waiting for FiniteAsyncRunner to stop")
                break
            }
            await _Concurrency.Task.yield()
        }
    }
}

actor LockedFlag {
    private(set) var value = false

    func set() {
        value = true
    }
}

actor IterationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

actor IterationLog {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }
}
