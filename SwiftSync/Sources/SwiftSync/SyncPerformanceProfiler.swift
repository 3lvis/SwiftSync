import Foundation

struct SyncPerformanceReport: Sendable {
    let totalsByPhase: [SyncPhase: Duration]

    func entered(_ phase: SyncPhase) -> Bool {
        totalsByPhase[phase] != nil
    }
}

private final class SyncPerformanceProfiler: @unchecked Sendable {
    private let clock = ContinuousClock()
    private let lock = NSLock()
    private var totalsByPhase: [SyncPhase: Duration] = [:]

    func measure<T>(_ phase: SyncPhase, operation: () throws -> T) rethrows -> T {
        let start = clock.now
        defer { record(phase: phase, duration: start.duration(to: clock.now)) }
        return try operation()
    }

    func measure<T>(_ phase: SyncPhase, operation: () async throws -> T) async rethrows -> T {
        let start = clock.now
        defer { record(phase: phase, duration: start.duration(to: clock.now)) }
        return try await operation()
    }

    func snapshot() -> SyncPerformanceReport {
        lock.lock()
        defer { lock.unlock() }
        return SyncPerformanceReport(totalsByPhase: totalsByPhase)
    }

    private func record(phase: SyncPhase, duration: Duration) {
        lock.lock()
        totalsByPhase[phase, default: .zero] += duration
        lock.unlock()
    }
}

private enum SyncPerformanceProfilingState {
    @TaskLocal static var current: SyncPerformanceProfiler?
}

func syncPerformanceProfile<T>(_ phase: SyncPhase, operation: () throws -> T) rethrows -> T {
    guard let profiler = SyncPerformanceProfilingState.current else {
        return try operation()
    }
    return try profiler.measure(phase, operation: operation)
}

func syncPerformanceProfile<T>(_ phase: SyncPhase, operation: () async throws -> T) async rethrows -> T {
    guard let profiler = SyncPerformanceProfilingState.current else {
        return try await operation()
    }
    return try await profiler.measure(phase, operation: operation)
}

extension SwiftSync {
    static func withPerformanceProfiling<T>(
        operation: () throws -> T
    ) rethrows -> (value: T, profile: SyncPerformanceReport) {
        let profiler = SyncPerformanceProfiler()
        let value = try SyncPerformanceProfilingState.$current.withValue(profiler) {
            try operation()
        }
        return (value, profiler.snapshot())
    }

    static func withPerformanceProfiling<T>(
        operation: () async throws -> T
    ) async rethrows -> (value: T, profile: SyncPerformanceReport) {
        let profiler = SyncPerformanceProfiler()
        let value = try await SyncPerformanceProfilingState.$current.withValue(profiler) {
            try await operation()
        }
        return (value, profiler.snapshot())
    }

    @MainActor
    static func withMainActorPerformanceProfiling<T>(
        operation: @MainActor () async throws -> T
    ) async rethrows -> (value: T, profile: SyncPerformanceReport) {
        let profiler = SyncPerformanceProfiler()
        let value = try await SyncPerformanceProfilingState.$current.withValue(profiler) {
            try await operation()
        }
        return (value, profiler.snapshot())
    }
}
