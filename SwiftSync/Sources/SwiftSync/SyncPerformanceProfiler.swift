import Foundation
import OSLog

struct SyncPerformanceProfile: Sendable {
    let totalsByPhase: [String: Duration]
}

final class SyncPerformanceProfiler: @unchecked Sendable {
    private static let signposter = OSSignposter(subsystem: "SwiftSync", category: "Performance")

    private let clock = ContinuousClock()
    private let lock = NSLock()
    private var totalsByPhase: [String: Duration] = [:]

    func measure<T>(_ phase: String, operation: () throws -> T) rethrows -> T {
        let interval = Self.signposter.beginInterval("SwiftSyncPhase", "\(phase, privacy: .public)")
        let start = clock.now
        defer {
            Self.signposter.endInterval("SwiftSyncPhase", interval)
            record(phase: phase, duration: start.duration(to: clock.now))
        }
        return try operation()
    }

    func measure<T>(_ phase: String, operation: () async throws -> T) async rethrows -> T {
        let interval = Self.signposter.beginInterval("SwiftSyncPhase", "\(phase, privacy: .public)")
        let start = clock.now
        defer {
            Self.signposter.endInterval("SwiftSyncPhase", interval)
            record(phase: phase, duration: start.duration(to: clock.now))
        }
        return try await operation()
    }

    func snapshot() -> SyncPerformanceProfile {
        lock.lock()
        defer { lock.unlock() }
        return SyncPerformanceProfile(totalsByPhase: totalsByPhase)
    }

    private func record(phase: String, duration: Duration) {
        lock.lock()
        totalsByPhase[phase, default: .zero] += duration
        lock.unlock()
    }
}

enum SyncPerformanceProfilingState {
    @TaskLocal static var current: SyncPerformanceProfiler?
}

func syncProfile<T>(_ phase: String, operation: () throws -> T) rethrows -> T {
    guard let profiler = SyncPerformanceProfilingState.current else {
        return try operation()
    }
    return try profiler.measure(phase, operation: operation)
}

func syncProfile<T>(_ phase: String, operation: () async throws -> T) async rethrows -> T {
    guard let profiler = SyncPerformanceProfilingState.current else {
        return try await operation()
    }
    return try await profiler.measure(phase, operation: operation)
}

extension SwiftSync {
    static func withPerformanceProfiling<T>(
        operation: () throws -> T
    ) rethrows -> (value: T, profile: SyncPerformanceProfile) {
        let profiler = SyncPerformanceProfiler()
        let value = try SyncPerformanceProfilingState.$current.withValue(profiler) {
            try operation()
        }
        return (value, profiler.snapshot())
    }

    static func withPerformanceProfiling<T>(
        operation: () async throws -> T
    ) async rethrows -> (value: T, profile: SyncPerformanceProfile) {
        let profiler = SyncPerformanceProfiler()
        let value = try await SyncPerformanceProfilingState.$current.withValue(profiler) {
            try await operation()
        }
        return (value, profiler.snapshot())
    }

    @MainActor
    static func withMainActorPerformanceProfiling<T>(
        operation: @MainActor () async throws -> T
    ) async rethrows -> (value: T, profile: SyncPerformanceProfile) {
        let profiler = SyncPerformanceProfiler()
        let value = try await SyncPerformanceProfilingState.$current.withValue(profiler) {
            try await operation()
        }
        return (value, profiler.snapshot())
    }
}
