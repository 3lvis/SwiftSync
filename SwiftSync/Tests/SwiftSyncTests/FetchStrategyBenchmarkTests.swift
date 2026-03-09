import XCTest
import SwiftData
@testable import SwiftSync

// Opt-in benchmark suite for fetch-strategy profiling.
// Default run: SWIFTSYNC_RUN_BENCHMARKS=1 swift test --filter FetchStrategyBenchmarkTests
// Full matrix example:
// SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_STORES=memory,sqlite \
// SWIFTSYNC_BENCHMARK_TIERS=1000,10000,50000 swift test --filter FetchStrategyBenchmarkTests

@Syncable
@Model
final class BenchmarkUser {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class BenchmarkTag {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class BenchmarkReviewer {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class BenchmarkProject {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class BenchmarkScopedTask {
    @Attribute(.unique) var id: Int
    var title: String
    var project: BenchmarkProject?

    init(id: Int, title: String, project: BenchmarkProject? = nil) {
        self.id = id
        self.title = title
        self.project = project
    }
}

extension BenchmarkScopedTask: ParentScopedModel {
    typealias SyncParent = BenchmarkProject
    static var parentRelationship: ReferenceWritableKeyPath<BenchmarkScopedTask, BenchmarkProject?> { \.project }
}

@Syncable
@Model
final class BenchmarkWorkItem {
    @Attribute(.unique) var id: Int
    var title: String
    var assignee: BenchmarkUser?
    var tags: [BenchmarkTag]
    var reviewers: [BenchmarkReviewer]

    init(
        id: Int,
        title: String,
        assignee: BenchmarkUser? = nil,
        tags: [BenchmarkTag] = [],
        reviewers: [BenchmarkReviewer] = []
    ) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.tags = tags
        self.reviewers = reviewers
    }
}

@MainActor
final class FetchStrategyBenchmarkTests: XCTestCase {
    private let environment = BenchmarkEnvironment.current

    func testGlobalBatchSyncBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let fixture = try makeStoreFixture(storeKind: storeKind)
                defer { fixture.cleanup() }

                let container = try ModelContainer(
                    for: BenchmarkUser.self,
                    configurations: fixture.configuration
                )
                let context = ModelContext(container)

                try seedUsers(count: existingCount, in: context)
                let payload = makeUserPayload(count: existingCount, namePrefix: "batch-updated")

                let result = try await measureCase(
                    name: "global-batch-sync",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: existingCount,
                    scopeRows: nil,
                    relationRows: nil
                ) {
                    try await SwiftSync.sync(payload: payload, as: BenchmarkUser.self, in: context)
                }

                emit(result)
            }
        }
    }

    func testSingleItemSyncBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let fixture = try makeStoreFixture(storeKind: storeKind)
                defer { fixture.cleanup() }

                let container = try ModelContainer(
                    for: BenchmarkUser.self,
                    configurations: fixture.configuration
                )
                let context = ModelContext(container)

                try seedUsers(count: existingCount, in: context)
                let payload: [String: Any] = [
                    "id": existingCount,
                    "full_name": "single-item-updated-\(existingCount)"
                ]

                let result = try await measureCase(
                    name: "single-item-sync",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: 1,
                    scopeRows: nil,
                    relationRows: nil
                ) {
                    try await SwiftSync.sync(item: payload, as: BenchmarkUser.self, in: context)
                }

                emit(result)
            }
        }
    }

    func testParentScopedBatchSyncBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let scopeCount = min(environment.scopeSize, existingCount)
                let fixture = try makeStoreFixture(storeKind: storeKind)
                defer { fixture.cleanup() }

                let container = try ModelContainer(
                    for: BenchmarkProject.self, BenchmarkScopedTask.self,
                    configurations: fixture.configuration
                )
                let context = ModelContext(container)
                let targetProject = try seedParentScopedTasks(
                    totalTaskCount: existingCount,
                    targetScopeCount: scopeCount,
                    in: context
                )
                let payload = makeScopedTaskPayload(count: scopeCount)

                let result = try await measureCase(
                    name: "parent-scoped-batch-sync",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: scopeCount,
                    scopeRows: scopeCount,
                    relationRows: nil
                ) {
                    try await SwiftSync.sync(
                        payload: payload,
                        as: BenchmarkScopedTask.self,
                        in: context,
                        parent: targetProject,
                        relationship: \BenchmarkScopedTask.project
                    )
                }

                emit(result)
            }
        }
    }

    func testToOneRelationshipResolutionBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for relatedCount in environment.datasetTiers {
                let fixture = try makeStoreFixture(storeKind: storeKind)
                defer { fixture.cleanup() }

                let container = try ModelContainer(
                    for: BenchmarkUser.self, BenchmarkWorkItem.self,
                    configurations: fixture.configuration
                )
                let context = ModelContext(container)

                try seedUsers(count: relatedCount, in: context)
                try seedWorkItem(id: 1, in: context)
                let payload: [String: Any] = [
                    "id": 1,
                    "title": "to-one-benchmark",
                    "assignee_id": relatedCount
                ]

                let result = try await measureCase(
                    name: "to-one-fk-resolution",
                    storeKind: storeKind,
                    totalRows: 1,
                    payloadRows: 1,
                    scopeRows: nil,
                    relationRows: relatedCount
                ) {
                    try await SwiftSync.sync(item: payload, as: BenchmarkWorkItem.self, in: context)
                }

                emit(result)
            }
        }
    }

    func testToManyForeignKeyResolutionBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for relatedCount in environment.datasetTiers {
                for linkCount in environment.relationshipCounts where linkCount <= relatedCount {
                    let fixture = try makeStoreFixture(storeKind: storeKind)
                    defer { fixture.cleanup() }

                    let container = try ModelContainer(
                        for: BenchmarkTag.self, BenchmarkWorkItem.self,
                        configurations: fixture.configuration
                    )
                    let context = ModelContext(container)

                    try seedTags(count: relatedCount, in: context)
                    try seedWorkItem(id: 1, in: context)
                    let payload: [String: Any] = [
                        "id": 1,
                        "title": "to-many-fk-benchmark",
                        "tag_ids": Array(1...linkCount)
                    ]

                    let result = try await measureCase(
                        name: "to-many-fk-resolution",
                        storeKind: storeKind,
                        totalRows: 1,
                        payloadRows: 1,
                        scopeRows: nil,
                        relationRows: relatedCount,
                        relationshipCount: linkCount
                    ) {
                        try await SwiftSync.sync(item: payload, as: BenchmarkWorkItem.self, in: context)
                    }

                    emit(result)
                }
            }
        }
    }

    func testToManyNestedRelationshipBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for relatedCount in environment.datasetTiers {
                for linkCount in environment.relationshipCounts where linkCount <= relatedCount {
                    let fixture = try makeStoreFixture(storeKind: storeKind)
                    defer { fixture.cleanup() }

                    let container = try ModelContainer(
                        for: BenchmarkReviewer.self, BenchmarkWorkItem.self,
                        configurations: fixture.configuration
                    )
                    let context = ModelContext(container)

                    try seedReviewers(count: relatedCount, in: context)
                    try seedWorkItem(id: 1, in: context)
                    let payload: [String: Any] = [
                        "id": 1,
                        "title": "to-many-nested-benchmark",
                        "reviewers": Array(1...linkCount).map { ["id": $0, "full_name": "Reviewer \($0) updated"] }
                    ]

                    let result = try await measureCase(
                        name: "to-many-nested-resolution",
                        storeKind: storeKind,
                        totalRows: 1,
                        payloadRows: 1,
                        scopeRows: nil,
                        relationRows: relatedCount,
                        relationshipCount: linkCount
                    ) {
                        try await SwiftSync.sync(item: payload, as: BenchmarkWorkItem.self, in: context)
                    }

                    emit(result)
                }
            }
        }
    }

    func testExportBenchmarks() throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let fixture = try makeStoreFixture(storeKind: storeKind)
                defer { fixture.cleanup() }

                let syncContainer = try SyncContainer(
                    for: BenchmarkUser.self,
                    configurations: fixture.configuration
                )
                try seedUsers(count: existingCount, in: syncContainer.mainContext)

                let result = try measureCase(
                    name: "export-all",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: nil,
                    scopeRows: nil,
                    relationRows: nil
                ) {
                    _ = try syncContainer.export(as: BenchmarkUser.self)
                }

                emit(result)
            }
        }
    }

    func testParentScopedExportBenchmarks() throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let scopeCount = min(environment.scopeSize, existingCount)
                let fixture = try makeStoreFixture(storeKind: storeKind)
                defer { fixture.cleanup() }

                let syncContainer = try SyncContainer(
                    for: BenchmarkProject.self, BenchmarkScopedTask.self,
                    configurations: fixture.configuration
                )
                let targetProject = try seedParentScopedTasks(
                    totalTaskCount: existingCount,
                    targetScopeCount: scopeCount,
                    in: syncContainer.mainContext
                )

                let result = try measureCase(
                    name: "export-parent-scope",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: nil,
                    scopeRows: scopeCount,
                    relationRows: nil
                ) {
                    _ = try syncContainer.export(as: BenchmarkScopedTask.self, parent: targetProject)
                }

                emit(result)
            }
        }
    }

    private func requireBenchmarksEnabled() throws {
        guard environment.isEnabled else {
            throw XCTSkip(
                "Set SWIFTSYNC_RUN_BENCHMARKS=1 to run fetch-strategy benchmarks. " +
                "Optional: SWIFTSYNC_BENCHMARK_STORES=memory,sqlite SWIFTSYNC_BENCHMARK_TIERS=1000,10000,50000"
            )
        }
    }

    private func makeStoreFixture(storeKind: BenchmarkStoreKind) throws -> BenchmarkStoreFixture {
        switch storeKind {
        case .memory:
            return BenchmarkStoreFixture(
                configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                cleanup: {}
            )
        case .sqlite:
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift-sync-bench-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storeURL = directory.appendingPathComponent("bench.store")
            let configuration = ModelConfiguration(url: storeURL)
            return BenchmarkStoreFixture(
                configuration: configuration,
                cleanup: {
                    try? SyncContainer._resetPersistentStoreFiles(for: [configuration])
                    try? FileManager.default.removeItem(at: directory)
                }
            )
        }
    }

    private func seedUsers(count: Int, in context: ModelContext) throws {
        for index in 1...count {
            context.insert(BenchmarkUser(id: index, fullName: "User \(index)"))
        }
        try context.save()
    }

    private func seedTags(count: Int, in context: ModelContext) throws {
        for index in 1...count {
            context.insert(BenchmarkTag(id: index, name: "Tag \(index)"))
        }
        try context.save()
    }

    private func seedReviewers(count: Int, in context: ModelContext) throws {
        for index in 1...count {
            context.insert(BenchmarkReviewer(id: index, fullName: "Reviewer \(index)"))
        }
        try context.save()
    }

    private func seedWorkItem(id: Int, in context: ModelContext) throws {
        context.insert(BenchmarkWorkItem(id: id, title: "Work Item \(id)"))
        try context.save()
    }

    private func seedParentScopedTasks(
        totalTaskCount: Int,
        targetScopeCount: Int,
        in context: ModelContext
    ) throws -> BenchmarkProject {
        let target = BenchmarkProject(id: 1, name: "Target")
        context.insert(target)

        let overflowParents = max(1, min(10, totalTaskCount - targetScopeCount))
        var otherParents: [BenchmarkProject] = []
        for index in 0..<overflowParents {
            let parent = BenchmarkProject(id: index + 2, name: "Other \(index + 2)")
            context.insert(parent)
            otherParents.append(parent)
        }

        for index in 1...targetScopeCount {
            context.insert(BenchmarkScopedTask(id: index, title: "Target \(index)", project: target))
        }

        if totalTaskCount > targetScopeCount {
            for offset in 0..<(totalTaskCount - targetScopeCount) {
                let taskID = targetScopeCount + offset + 1
                let parent = otherParents[offset % otherParents.count]
                context.insert(BenchmarkScopedTask(id: taskID, title: "Other \(taskID)", project: parent))
            }
        }

        try context.save()
        return target
    }

    private func makeUserPayload(count: Int, namePrefix: String) -> [[String: Any]] {
        (1...count).map { index in
            ["id": index, "full_name": "\(namePrefix) \(index)"]
        }
    }

    private func makeScopedTaskPayload(count: Int) -> [[String: Any]] {
        (1...count).map { index in
            ["id": index, "title": "Scoped Updated \(index)"]
        }
    }

    private func measureCase(
        name: String,
        storeKind: BenchmarkStoreKind,
        totalRows: Int,
        payloadRows: Int?,
        scopeRows: Int?,
        relationRows: Int?,
        relationshipCount: Int? = nil,
        operation: () throws -> Void
    ) throws -> BenchmarkResult {
        let clock = ContinuousClock()
        let start = clock.now
        try operation()
        let duration = start.duration(to: clock.now)
        return BenchmarkResult(
            name: name,
            storeKind: storeKind,
            totalRows: totalRows,
            payloadRows: payloadRows,
            scopeRows: scopeRows,
            relationRows: relationRows,
            relationshipCount: relationshipCount,
            duration: duration
        )
    }

    private func measureCase(
        name: String,
        storeKind: BenchmarkStoreKind,
        totalRows: Int,
        payloadRows: Int?,
        scopeRows: Int?,
        relationRows: Int?,
        relationshipCount: Int? = nil,
        operation: @MainActor () async throws -> Void
    ) async throws -> BenchmarkResult {
        let clock = ContinuousClock()
        let start = clock.now
        try await operation()
        let duration = start.duration(to: clock.now)
        return BenchmarkResult(
            name: name,
            storeKind: storeKind,
            totalRows: totalRows,
            payloadRows: payloadRows,
            scopeRows: scopeRows,
            relationRows: relationRows,
            relationshipCount: relationshipCount,
            duration: duration
        )
    }

    private func emit(_ result: BenchmarkResult) {
        print(result.rendered)
    }
}

private struct BenchmarkStoreFixture {
    let configuration: ModelConfiguration
    let cleanup: () -> Void
}

private enum BenchmarkStoreKind: String {
    case memory
    case sqlite
}

private struct BenchmarkEnvironment {
    let isEnabled: Bool
    let storeKinds: [BenchmarkStoreKind]
    let datasetTiers: [Int]
    let relationshipCounts: [Int]
    let scopeSize: Int

    static var current: BenchmarkEnvironment {
        let environment = ProcessInfo.processInfo.environment
        return BenchmarkEnvironment(
            isEnabled: environment["SWIFTSYNC_RUN_BENCHMARKS"] == "1",
            storeKinds: parseStoreKinds(environment["SWIFTSYNC_BENCHMARK_STORES"]) ?? [.memory],
            datasetTiers: parseIntegers(environment["SWIFTSYNC_BENCHMARK_TIERS"]) ?? [1_000],
            relationshipCounts: parseIntegers(environment["SWIFTSYNC_BENCHMARK_RELATIONSHIP_COUNTS"]) ?? [1, 10, 50],
            scopeSize: parseIntegers(environment["SWIFTSYNC_BENCHMARK_SCOPE_SIZE"])?.first ?? 100
        )
    }

    private static func parseStoreKinds(_ rawValue: String?) -> [BenchmarkStoreKind]? {
        guard let rawValue else { return nil }
        let values = rawValue
            .split(separator: ",")
            .compactMap { BenchmarkStoreKind(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return values.isEmpty ? nil : values
    }

    private static func parseIntegers(_ rawValue: String?) -> [Int]? {
        guard let rawValue else { return nil }
        let values = rawValue
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return values.isEmpty ? nil : values
    }
}

private struct BenchmarkResult {
    let name: String
    let storeKind: BenchmarkStoreKind
    let totalRows: Int
    let payloadRows: Int?
    let scopeRows: Int?
    let relationRows: Int?
    let relationshipCount: Int?
    let duration: Duration

    var rendered: String {
        var parts: [String] = [
            "[SwiftSyncBenchmark]",
            "case=\(name)",
            "store=\(storeKind.rawValue)",
            "totalRows=\(totalRows)",
            "durationMs=\(duration.inMilliseconds)"
        ]
        if let payloadRows {
            parts.append("payloadRows=\(payloadRows)")
        }
        if let scopeRows {
            parts.append("scopeRows=\(scopeRows)")
        }
        if let relationRows {
            parts.append("relationRows=\(relationRows)")
        }
        if let relationshipCount {
            parts.append("relationshipCount=\(relationshipCount)")
        }
        return parts.joined(separator: " ")
    }
}

private extension Duration {
    var inMilliseconds: String {
        let components = self.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f", milliseconds)
    }
}
