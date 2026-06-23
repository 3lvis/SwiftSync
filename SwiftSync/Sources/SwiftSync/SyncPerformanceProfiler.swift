import Foundation

/// A measured step of a sync operation. The raw value is the key under which `SyncPerformanceProfiler`
/// accumulates the step's duration — and the label shown in the benchmark's per-phase report.
enum SyncPhase: String {
    case normalizePayload = "normalize-payload"
    case fetchExisting = "fetch-existing"
    case fetchExistingByIdentity = "fetch-existing-by-identity"
    case fetchExistingByParent = "fetch-existing-by-parent"
    case findExisting = "find-existing"
    case filterScope = "filter-scope"
    case fetchParents = "fetch-parents"
    case resolveParent = "resolve-parent"
    case createModel = "create-model"
    case buildIndex = "build-index"
    case applyFields = "apply-fields"
    case applyParent = "apply-parent"
    case applyRelationships = "apply-relationships"
    case deleteDuplicates = "delete-duplicates"
    case deleteMissing = "delete-missing"
    case saveContext = "save-context"
    case relationshipFetch = "relationship-fetch"
    case relationshipFetchByIdentity = "relationship-fetch-by-identity"
    case relationshipIndexByID = "relationship-index-by-id"
    case relationshipApplyToOneForeignKey = "relationship-apply-to-one-foreign-key"
    case relationshipApplyToManyForeignKeys = "relationship-apply-to-many-foreign-keys"
    case relationshipApplyToOneNestedObject = "relationship-apply-to-one-nested-object"
    case relationshipApplyToManyNestedObjects = "relationship-apply-to-many-nested-objects"
}

struct SyncPerformanceReport: Sendable {
    let totalsByPhase: [SyncPhase: Duration]

    func entered(_ phase: SyncPhase) -> Bool {
        totalsByPhase[phase] != nil
    }
}

private final class SyncPerformanceProfiler: @unchecked Sendable {
    @TaskLocal static var current: SyncPerformanceProfiler?

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

func syncPerformanceProfile<T>(_ phase: SyncPhase, operation: () throws -> T) rethrows -> T {
    guard let profiler = SyncPerformanceProfiler.current else {
        return try operation()
    }
    return try profiler.measure(phase, operation: operation)
}

func syncPerformanceProfile<T>(_ phase: SyncPhase, operation: () async throws -> T) async rethrows -> T {
    guard let profiler = SyncPerformanceProfiler.current else {
        return try await operation()
    }
    return try await profiler.measure(phase, operation: operation)
}

extension SwiftSync {
    static func withPerformanceProfiling<T>(
        operation: () throws -> T
    ) rethrows -> (value: T, profile: SyncPerformanceReport) {
        let profiler = SyncPerformanceProfiler()
        let value = try SyncPerformanceProfiler.$current.withValue(profiler) {
            try operation()
        }
        return (value, profiler.snapshot())
    }

    static func withPerformanceProfiling<T>(
        operation: () async throws -> T
    ) async rethrows -> (value: T, profile: SyncPerformanceReport) {
        let profiler = SyncPerformanceProfiler()
        let value = try await SyncPerformanceProfiler.$current.withValue(profiler) {
            try await operation()
        }
        return (value, profiler.snapshot())
    }

    @MainActor
    static func withMainActorPerformanceProfiling<T>(
        operation: @MainActor () async throws -> T
    ) async rethrows -> (value: T, profile: SyncPerformanceReport) {
        let profiler = SyncPerformanceProfiler()
        let value = try await SyncPerformanceProfiler.$current.withValue(profiler) {
            try await operation()
        }
        return (value, profiler.snapshot())
    }
}
