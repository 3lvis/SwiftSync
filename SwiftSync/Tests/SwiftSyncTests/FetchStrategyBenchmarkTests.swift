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

@Syncable
@Model
final class ScenarioUser {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class ScenarioTag {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class ScenarioProject {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class ScenarioTask {
    @Attribute(.unique) var id: Int
    var title: String
    var project: ScenarioProject?
    var assignee: ScenarioUser?

    @RemoteKey("tag_ids")
    var tags: [ScenarioTag]

    @RemoteKey("watcher_ids")
    var watchers: [ScenarioUser]

    init(
        id: Int,
        title: String,
        project: ScenarioProject? = nil,
        assignee: ScenarioUser? = nil,
        tags: [ScenarioTag] = [],
        watchers: [ScenarioUser] = []
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.assignee = assignee
        self.tags = tags
        self.watchers = watchers
    }
}

extension ScenarioTask: ParentScopedModel {
    typealias SyncParent = ScenarioProject
    static var parentRelationship: ReferenceWritableKeyPath<ScenarioTask, ScenarioProject?> { \.project }
}

@MainActor
final class FetchStrategyBenchmarkTests: XCTestCase {
    private let environment = BenchmarkEnvironment.current

    func testGlobalBatchSyncBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let result = try await measureRepeatedAsyncCase(
                    name: "global-batch-sync",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: existingCount,
                    scopeRows: nil,
                    relationRows: nil
                ) {
                    let fixture = try makeStoreFixture(storeKind: storeKind)
                    defer { fixture.cleanup() }

                    let container = try ModelContainer(
                        for: BenchmarkUser.self,
                        configurations: fixture.configuration
                    )
                    let context = ModelContext(container)

                    try seedUsers(count: existingCount, in: context)
                    let payload = makeUserPayload(count: existingCount, namePrefix: "batch-updated")
                    return try await measureDuration {
                        try await SwiftSync.sync(payload: payload, as: BenchmarkUser.self, in: context)
                    }
                }

                emit(result)
            }
        }
    }

    func testSingleItemSyncBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let result = try await measureRepeatedAsyncCase(
                    name: "single-item-sync",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: 1,
                    scopeRows: nil,
                    relationRows: nil
                ) {
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
                    return try await measureDuration {
                        try await SwiftSync.sync(item: payload, as: BenchmarkUser.self, in: context)
                    }
                }

                emit(result)
            }
        }
    }

    func testParentScopedSingleItemSyncBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let scopeCount = min(environment.scopeSize, existingCount)
                let result = try await measureRepeatedAsyncCase(
                    name: "parent-scoped-single-item-sync",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: 1,
                    scopeRows: scopeCount,
                    relationRows: nil
                ) {
                    let fixture = try makeStoreFixture(storeKind: storeKind)
                    defer { fixture.cleanup() }

                    let container = try ModelContainer(
                        for: BenchmarkProject.self,
                        BenchmarkScopedTask.self,
                        configurations: fixture.configuration
                    )
                    let context = ModelContext(container)

                    let targetProject = try seedParentScopedTasks(
                        totalTaskCount: existingCount,
                        targetScopeCount: scopeCount,
                        in: context
                    )

                    let payload: [String: Any] = [
                        "id": 1,
                        "title": "Scoped Item Updated"
                    ]
                    return try await measureDuration {
                        try await SwiftSync.sync(
                            item: payload,
                            as: BenchmarkScopedTask.self,
                            in: context,
                            parent: targetProject,
                            relationship: \BenchmarkScopedTask.project
                        )
                    }
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
                let result = try await measureRepeatedAsyncCase(
                    name: "parent-scoped-batch-sync",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: scopeCount,
                    scopeRows: scopeCount,
                    relationRows: nil
                ) {
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
                    return try await measureDuration {
                        try await SwiftSync.sync(
                            payload: payload,
                            as: BenchmarkScopedTask.self,
                            in: context,
                            parent: targetProject,
                            relationship: \BenchmarkScopedTask.project
                        )
                    }
                }

                emit(result)
            }
        }
    }

    func testToOneRelationshipResolutionBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for relatedCount in environment.datasetTiers {
                let result = try await measureRepeatedAsyncCase(
                    name: "to-one-fk-resolution",
                    storeKind: storeKind,
                    totalRows: 1,
                    payloadRows: 1,
                    scopeRows: nil,
                    relationRows: relatedCount
                ) {
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
                    return try await measureDuration {
                        try await SwiftSync.sync(item: payload, as: BenchmarkWorkItem.self, in: context)
                    }
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
                    let result = try await measureRepeatedAsyncCase(
                        name: "to-many-fk-resolution",
                        storeKind: storeKind,
                        totalRows: 1,
                        payloadRows: 1,
                        scopeRows: nil,
                        relationRows: relatedCount,
                        relationshipCount: linkCount
                    ) {
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
                        return try await measureDuration {
                            try await SwiftSync.sync(item: payload, as: BenchmarkWorkItem.self, in: context)
                        }
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
                    let result = try await measureRepeatedAsyncCase(
                        name: "to-many-nested-resolution",
                        storeKind: storeKind,
                        totalRows: 1,
                        payloadRows: 1,
                        scopeRows: nil,
                        relationRows: relatedCount,
                        relationshipCount: linkCount
                    ) {
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
                        return try await measureDuration {
                            try await SwiftSync.sync(item: payload, as: BenchmarkWorkItem.self, in: context)
                        }
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
                let result = try measureRepeatedCase(
                    name: "export-all",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: nil,
                    scopeRows: nil,
                    relationRows: nil
                ) {
                    let fixture = try makeStoreFixture(storeKind: storeKind)
                    defer { fixture.cleanup() }

                    let syncContainer = try SyncContainer(
                        for: BenchmarkUser.self,
                        configurations: fixture.configuration
                    )
                    try seedUsers(count: existingCount, in: syncContainer.mainContext)
                    return try measureDuration {
                        _ = try syncContainer.export(as: BenchmarkUser.self)
                    }
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
                let result = try measureRepeatedCase(
                    name: "export-parent-scope",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: nil,
                    scopeRows: scopeCount,
                    relationRows: nil
                ) {
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
                    return try measureDuration {
                        _ = try syncContainer.export(as: BenchmarkScopedTask.self, parent: targetProject)
                    }
                }

                emit(result)
            }
        }
    }

    func testMixedWorkloadBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let scopeCount = min(environment.scopeSize, existingCount)
                let relatedCount = existingCount
                let relationshipCount = min(10, relatedCount)

                let result = try await measureRepeatedAsyncCase(
                    name: "mixed-session-workload",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: scopeCount + 2,
                    scopeRows: scopeCount,
                    relationRows: relatedCount,
                    relationshipCount: relationshipCount,
                    workload: "mixed"
                ) {
                    let fixture = try makeStoreFixture(storeKind: storeKind)
                    defer { fixture.cleanup() }

                    let container = try ModelContainer(
                        for: BenchmarkUser.self,
                        BenchmarkTag.self,
                        BenchmarkReviewer.self,
                        BenchmarkProject.self,
                        BenchmarkScopedTask.self,
                        BenchmarkWorkItem.self,
                        configurations: fixture.configuration
                    )
                    let context = ModelContext(container)
                    let syncContainer = SyncContainer(container)

                    try seedUsers(count: relatedCount, in: context)
                    try seedTags(count: relatedCount, in: context)
                    try seedReviewers(count: relatedCount, in: context)
                    let targetProject = try seedParentScopedTasks(
                        totalTaskCount: existingCount,
                        targetScopeCount: scopeCount,
                        in: context
                    )
                    try seedWorkItem(id: 1, in: context)

                    let scopedPayload = makeScopedTaskPayload(count: scopeCount)
                    let userPayload: [String: Any] = [
                        "id": relatedCount,
                        "full_name": "Mixed User \(relatedCount)"
                    ]
                    let workItemPayload: [String: Any] = [
                        "id": 1,
                        "title": "Mixed Work Item",
                        "assignee_id": relatedCount,
                        "tag_ids": Array(1...relationshipCount),
                        "reviewers": Array(1...relationshipCount).map {
                            ["id": $0, "full_name": "Reviewer \($0) mixed"]
                        }
                    ]

                    return try await measureDuration {
                        try await SwiftSync.sync(item: userPayload, as: BenchmarkUser.self, in: context)
                        try await SwiftSync.sync(
                            payload: scopedPayload,
                            as: BenchmarkScopedTask.self,
                            in: context,
                            parent: targetProject,
                            relationship: \BenchmarkScopedTask.project
                        )
                        try await SwiftSync.sync(item: workItemPayload, as: BenchmarkWorkItem.self, in: context)
                        _ = try syncContainer.export(as: BenchmarkScopedTask.self, parent: targetProject)
                    }
                }

                emit(result)
            }
        }
    }

    func testDemoShapedScenarioBenchmarks() async throws {
        try requireBenchmarksEnabled()

        for storeKind in environment.storeKinds {
            for existingCount in environment.datasetTiers {
                let scopeCount = min(environment.scopeSize, existingCount)
                let relationshipCount = min(10, max(1, existingCount))

                let result = try await measureRepeatedAsyncCase(
                    name: "demo-shaped-project-session",
                    storeKind: storeKind,
                    totalRows: existingCount,
                    payloadRows: scopeCount + 2,
                    scopeRows: scopeCount,
                    relationRows: existingCount,
                    relationshipCount: relationshipCount,
                    workload: "mixed"
                ) {
                    let fixture = try makeStoreFixture(storeKind: storeKind)
                    defer { fixture.cleanup() }

                    let container = try ModelContainer(
                        for: ScenarioUser.self,
                        ScenarioTag.self,
                        ScenarioProject.self,
                        ScenarioTask.self,
                        configurations: fixture.configuration
                    )
                    let context = ModelContext(container)
                    let syncContainer = SyncContainer(container)

                    let targetProject = try seedScenarioWorkspace(
                        totalTaskCount: existingCount,
                        targetScopeCount: scopeCount,
                        relatedCount: existingCount,
                        in: context
                    )

                    let taskListPayload = makeScenarioTaskListPayload(
                        count: scopeCount,
                        relationshipCount: relationshipCount
                    )
                    let taskDetailPayload: [String: Any] = [
                        "id": 1,
                        "title": "Scenario Task 1 Detail Updated",
                        "assignee_id": existingCount,
                        "tag_ids": Array(1...relationshipCount),
                        "watcher_ids": Array(max(1, existingCount - relationshipCount + 1)...existingCount)
                    ]
                    let userPresencePayload: [String: Any] = [
                        "id": existingCount,
                        "full_name": "Scenario User \(existingCount) Active"
                    ]

                    return try await measureDuration {
                        try await SwiftSync.sync(
                            payload: taskListPayload,
                            as: ScenarioTask.self,
                            in: context,
                            parent: targetProject,
                            relationship: \ScenarioTask.project
                        )
                        try await SwiftSync.sync(item: taskDetailPayload, as: ScenarioTask.self, in: context)
                        try await SwiftSync.sync(item: userPresencePayload, as: ScenarioUser.self, in: context)
                        _ = try syncContainer.export(as: ScenarioTask.self, parent: targetProject)
                    }
                }

                emit(result)
            }
        }
    }

    private func requireBenchmarksEnabled() throws {
        guard environment.isEnabled else {
            throw XCTSkip(
                "Set SWIFTSYNC_RUN_BENCHMARKS=1 to run fetch-strategy benchmarks. " +
                "Optional: SWIFTSYNC_BENCHMARK_STORES=memory,sqlite " +
                "SWIFTSYNC_BENCHMARK_TIERS=1000,10000,50000 " +
                "SWIFTSYNC_BENCHMARK_PROFILE_PHASES=1"
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

    private func seedScenarioWorkspace(
        totalTaskCount: Int,
        targetScopeCount: Int,
        relatedCount: Int,
        in context: ModelContext
    ) throws -> ScenarioProject {
        for index in 1...relatedCount {
            context.insert(ScenarioUser(id: index, fullName: "Scenario User \(index)"))
            context.insert(ScenarioTag(id: index, name: "Scenario Tag \(index)"))
        }

        let targetProject = ScenarioProject(id: 1, name: "Project 1")
        context.insert(targetProject)

        let otherProjectCount = max(1, min(8, totalTaskCount - targetScopeCount))
        var otherProjects: [ScenarioProject] = []
        for index in 0..<otherProjectCount {
            let project = ScenarioProject(id: index + 2, name: "Project \(index + 2)")
            context.insert(project)
            otherProjects.append(project)
        }

        for index in 1...targetScopeCount {
            context.insert(ScenarioTask(id: index, title: "Scenario Task \(index)", project: targetProject))
        }

        if totalTaskCount > targetScopeCount {
            for offset in 0..<(totalTaskCount - targetScopeCount) {
                let taskID = targetScopeCount + offset + 1
                let project = otherProjects[offset % otherProjects.count]
                context.insert(ScenarioTask(id: taskID, title: "Scenario Task \(taskID)", project: project))
            }
        }

        try context.save()
        return targetProject
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

    private func makeScenarioTaskListPayload(
        count: Int,
        relationshipCount: Int
    ) -> [[String: Any]] {
        (1...count).map { index in
            [
                "id": index,
                "title": "Scenario Task \(index) List Updated",
                "assignee_id": ((index - 1) % max(1, count)) + 1,
                "tag_ids": Array(1...relationshipCount),
                "watcher_ids": Array(1...relationshipCount)
            ]
        }
    }

    private func measureRepeatedCase(
        name: String,
        storeKind: BenchmarkStoreKind,
        totalRows: Int,
        payloadRows: Int?,
        scopeRows: Int?,
        relationRows: Int?,
        relationshipCount: Int? = nil,
        workload: String = "isolated",
        operation: () throws -> BenchmarkMeasurement
    ) throws -> BenchmarkSummary {
        var measurements: [BenchmarkMeasurement] = []
        measurements.reserveCapacity(environment.sampleCount)
        for _ in 0..<environment.sampleCount {
            measurements.append(try operation())
        }
        return BenchmarkSummary(
            name: name,
            storeKind: storeKind,
            totalRows: totalRows,
            payloadRows: payloadRows,
            scopeRows: scopeRows,
            relationRows: relationRows,
            relationshipCount: relationshipCount,
            workload: workload,
            durations: measurements.map(\.duration),
            phaseProfiles: BenchmarkPhaseProfile.build(from: measurements)
        )
    }

    private func measureRepeatedAsyncCase(
        name: String,
        storeKind: BenchmarkStoreKind,
        totalRows: Int,
        payloadRows: Int?,
        scopeRows: Int?,
        relationRows: Int?,
        relationshipCount: Int? = nil,
        workload: String = "isolated",
        operation: @MainActor () async throws -> BenchmarkMeasurement
    ) async throws -> BenchmarkSummary {
        var measurements: [BenchmarkMeasurement] = []
        measurements.reserveCapacity(environment.sampleCount)
        for _ in 0..<environment.sampleCount {
            measurements.append(try await operation())
        }
        return BenchmarkSummary(
            name: name,
            storeKind: storeKind,
            totalRows: totalRows,
            payloadRows: payloadRows,
            scopeRows: scopeRows,
            relationRows: relationRows,
            relationshipCount: relationshipCount,
            workload: workload,
            durations: measurements.map(\.duration),
            phaseProfiles: BenchmarkPhaseProfile.build(from: measurements)
        )
    }

    private func measureDuration(
        operation: () throws -> Void
    ) throws -> BenchmarkMeasurement {
        let clock = ContinuousClock()
        let start = clock.now
        if environment.phaseProfilingEnabled {
            let (_, profile) = try SwiftSync.withPerformanceProfiling {
                try operation()
            }
            return BenchmarkMeasurement(
                duration: start.duration(to: clock.now),
                phaseTotals: profile.totalsByPhase
            )
        }
        try operation()
        return BenchmarkMeasurement(
            duration: start.duration(to: clock.now),
            phaseTotals: [:]
        )
    }

    private func measureDuration(
        operation: @MainActor () async throws -> Void
    ) async throws -> BenchmarkMeasurement {
        let clock = ContinuousClock()
        let start = clock.now
        if environment.phaseProfilingEnabled {
            let (_, profile) = try await SwiftSync.withMainActorPerformanceProfiling {
                try await operation()
            }
            return BenchmarkMeasurement(
                duration: start.duration(to: clock.now),
                phaseTotals: profile.totalsByPhase
            )
        }
        try await operation()
        return BenchmarkMeasurement(
            duration: start.duration(to: clock.now),
            phaseTotals: [:]
        )
    }

    private func emit(_ result: BenchmarkSummary) {
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
    let sampleCount: Int
    let phaseProfilingEnabled: Bool

    static var current: BenchmarkEnvironment {
        from(ProcessInfo.processInfo.environment)
    }

    static func from(_ environment: [String: String]) -> BenchmarkEnvironment {
        return BenchmarkEnvironment(
            isEnabled: environment["SWIFTSYNC_RUN_BENCHMARKS"] == "1",
            storeKinds: parseStoreKinds(environment["SWIFTSYNC_BENCHMARK_STORES"]) ?? [.memory],
            datasetTiers: parseIntegers(environment["SWIFTSYNC_BENCHMARK_TIERS"]) ?? [1_000],
            relationshipCounts: parseIntegers(environment["SWIFTSYNC_BENCHMARK_RELATIONSHIP_COUNTS"]) ?? [1, 10, 50],
            scopeSize: parseIntegers(environment["SWIFTSYNC_BENCHMARK_SCOPE_SIZE"])?.first ?? 100,
            sampleCount: max(1, parseIntegers(environment["SWIFTSYNC_BENCHMARK_SAMPLES"])?.first ?? 3),
            phaseProfilingEnabled: environment["SWIFTSYNC_BENCHMARK_PROFILE_PHASES"] == "1"
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

private struct BenchmarkSummary {
    let name: String
    let storeKind: BenchmarkStoreKind
    let totalRows: Int
    let payloadRows: Int?
    let scopeRows: Int?
    let relationRows: Int?
    let relationshipCount: Int?
    let workload: String
    let durations: [Duration]
    let phaseProfiles: [BenchmarkPhaseProfile]

    var rendered: String {
        var parts: [String] = [
            "[SwiftSyncBenchmark]",
            "case=\(name)",
            "store=\(storeKind.rawValue)",
            "totalRows=\(totalRows)",
            "workload=\(workload)",
            "samples=\(durations.count)",
            "medianMs=\(median.inMilliseconds)",
            "maxMs=\(max.inMilliseconds)"
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
        if !phaseProfiles.isEmpty {
            let medians = phaseProfiles
                .sorted { $0.name < $1.name }
                .map { "\($0.name):\($0.median.inMilliseconds)" }
                .joined(separator: ",")
            parts.append("phaseMedianMs=\(medians)")
        }
        return parts.joined(separator: " ")
    }

    private var sortedDurations: [Duration] {
        durations.sorted { $0.millisecondsValue < $1.millisecondsValue }
    }

    private var median: Duration {
        sortedDurations[sortedDurations.count / 2]
    }

    private var max: Duration {
        sortedDurations.last ?? .zero
    }
}

private struct BenchmarkMeasurement {
    let duration: Duration
    let phaseTotals: [String: Duration]
}

private struct BenchmarkPhaseProfile {
    let name: String
    let durations: [Duration]

    var median: Duration {
        durations.sorted { $0.millisecondsValue < $1.millisecondsValue }[durations.count / 2]
    }

    static func build(from measurements: [BenchmarkMeasurement]) -> [BenchmarkPhaseProfile] {
        var durationsByPhase: [String: [Duration]] = [:]
        for measurement in measurements {
            for (phase, duration) in measurement.phaseTotals {
                durationsByPhase[phase, default: []].append(duration)
            }
        }
        return durationsByPhase
            .map { BenchmarkPhaseProfile(name: $0.key, durations: $0.value) }
            .sorted { $0.name < $1.name }
    }
}

private extension Duration {
    static func milliseconds(_ value: Double) -> Duration {
        .seconds(value / 1_000)
    }

    var inMilliseconds: String {
        String(format: "%.3f", millisecondsValue)
    }

    var millisecondsValue: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

final class BenchmarkProfilingSupportTests: XCTestCase {
    func testEnvironmentParsesPhaseProfilingFlag() {
        let environment = BenchmarkEnvironment.from(
            [
                "SWIFTSYNC_RUN_BENCHMARKS": "1",
                "SWIFTSYNC_BENCHMARK_PROFILE_PHASES": "1"
            ]
        )

        XCTAssertTrue(environment.isEnabled)
        XCTAssertTrue(environment.phaseProfilingEnabled)
    }

    func testRenderedSummaryIncludesPhaseMedianBreakdown() {
        let summary = BenchmarkSummary(
            name: "demo-shaped-project-session",
            storeKind: .sqlite,
            totalRows: 10_000,
            payloadRows: 102,
            scopeRows: 100,
            relationRows: 10_000,
            relationshipCount: 10,
            workload: "mixed",
            durations: [.milliseconds(7000), .milliseconds(7100), .milliseconds(7200)],
            phaseProfiles: [
                BenchmarkPhaseProfile(
                    name: "fetch-existing",
                    durations: [.milliseconds(1000), .milliseconds(1100), .milliseconds(1200)]
                ),
                BenchmarkPhaseProfile(
                    name: "apply-relationships",
                    durations: [.milliseconds(3000), .milliseconds(3200), .milliseconds(3100)]
                )
            ]
        )

        XCTAssertTrue(summary.rendered.contains("phaseMedianMs=apply-relationships:3100.000,fetch-existing:1100.000"))
    }
}
