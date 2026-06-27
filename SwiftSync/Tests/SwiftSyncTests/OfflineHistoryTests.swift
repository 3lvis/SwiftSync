import SwiftData
import XCTest

@testable import SwiftSync

@Syncable
@Model
final class HistoryRow {
    @Attribute(.unique, .preserveValueOnDeletion) var id: String
    var title: String
    var updatedAt: Date

    init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

@MainActor
final class OfflineHistoryTests: XCTestCase {
    /// `pendingChanges` reads local history (ignoring inbound writes) and recovers a deleted row's id
    /// from the tombstone — with zero offline fields on the model.
    func testPendingChangesReadsLocalHistoryAndIgnoresInbound() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("bench.store"))
        let container = try SyncContainer(for: HistoryRow.self, configurations: configuration)
        let now = Date()

        // inboundAuthor marks this as a pull write, which pendingChanges must ignore.
        let inbound = ModelContext(container.modelContainer)
        inbound.author = SwiftSync.inboundAuthor
        inbound.insert(HistoryRow(id: "server-1", title: "From server", updatedAt: now))
        try inbound.save()

        // Default author marks a local write, detected as pending.
        let local = container.mainContext
        local.insert(HistoryRow(id: "local-1", title: "Made offline", updatedAt: now))
        try local.save()

        let pending = try SwiftSync.pendingChanges(for: HistoryRow.self, in: local)
        XCTAssertEqual(pending.inserts, ["local-1"], "inbound row must be ignored; local insert detected")
        XCTAssertTrue(pending.updates.isEmpty)
        XCTAssertTrue(pending.deletes.isEmpty)

        // Push first so the row is synced; the later delete is then a genuine pending deletion,
        // not an insert-then-delete the server never saw.
        _ = try await SwiftSync.withPendingChanges(for: HistoryRow.self, in: local) { _ in [] }

        // Plain context.delete — no special API; the id must still come back from the tombstone.
        let row = try XCTUnwrap(
            try local.fetch(FetchDescriptor<HistoryRow>(predicate: #Predicate { $0.id == "local-1" })).first)
        local.delete(row)
        try local.save()

        let afterDelete = try SwiftSync.pendingChanges(for: HistoryRow.self, in: local)
        XCTAssertEqual(
            afterDelete.deletes, ["local-1"],
            "deleted row's id must be recovered from the history tombstone")
    }

    func testInboundSyncTrimsOnlySwiftSyncAuthoredHistory() async throws {
        XCTAssertEqual(SwiftSync.inboundAuthor, "com.github.3lvis.SwiftSync.inbound")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbound-history-trim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("test.store"))
        let container = try SyncContainer(for: HistoryRow.self, configurations: configuration)
        let now = Date()

        let local = container.mainContext
        local.insert(HistoryRow(id: "local-1", title: "Local", updatedAt: now))
        try local.save()

        let widget = ModelContext(container.modelContainer)
        widget.author = "widget"
        widget.insert(HistoryRow(id: "widget-1", title: "Widget", updatedAt: now))
        try widget.save()

        try await container.sync(
            payload: [["id": "server-1", "title": "Server", "updated_at": ISO8601DateFormatter().string(from: now)]],
            as: HistoryRow.self
        )

        let history = try local.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        XCTAssertFalse(history.contains { $0.author == SwiftSync.inboundAuthor })
        XCTAssertTrue(history.contains { $0.author == nil })
        XCTAssertTrue(history.contains { $0.author == "widget" })

        let pending = try SwiftSync.pendingChanges(for: HistoryRow.self, in: local)
        XCTAssertEqual(Set(pending.inserts), Set(["local-1", "widget-1"]))
    }

    /// Opt-in benchmark. Expectation: ~baseline, because offline tracking reads history at push time
    /// rather than writing extra rows on the pull path.
    ///   SWIFTSYNC_RUN_BENCHMARKS=1 SWIFTSYNC_BENCHMARK_TIERS=100000 \
    ///     swift test --filter OfflineHistoryTests/testBulkPullOverhead
    func testBulkPullOverhead() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SWIFTSYNC_RUN_BENCHMARKS"] == "1",
            "Set SWIFTSYNC_RUN_BENCHMARKS=1 to run.")
        let tiers =
            (ProcessInfo.processInfo.environment["SWIFTSYNC_BENCHMARK_TIERS"]?
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }).flatMap {
                $0.isEmpty ? nil : $0
            } ?? [100_000]

        for count in tiers {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("offline-bulkpull-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("bench.store"))
            let container = try SyncContainer(for: HistoryRow.self, configurations: configuration)
            let context = ModelContext(container.modelContainer)
            context.author = SwiftSync.inboundAuthor

            let stamp = ISO8601DateFormatter().string(from: Date())
            let payload: [Any] = (0..<count).map { ["id": "row-\($0)", "title": "Row \($0)", "updated_at": stamp] }

            let clock = ContinuousClock()
            let pullStart = clock.now
            try await context.sync(payload: payload, as: HistoryRow.self, keyStyle: .snakeCase)
            let pullMs = pullStart.duration(to: clock.now).msValue

            let cleanupStart = clock.now
            try context.trimSwiftSyncInboundHistory()
            let cleanupMs = cleanupStart.duration(to: clock.now).msValue

            // Push-side detection should be ~empty and fast: every row was inbound-authored.
            let detectStart = clock.now
            let pending = try SwiftSync.pendingChanges(for: HistoryRow.self, in: context, since: nil)
            let detectMs = detectStart.duration(to: clock.now).msValue

            print(
                String(
                    format: "[OfflineHistory] rows=%d pullMs=%.1f cleanupMs=%.1f detectMs=%.1f pendingInserts=%d",
                    count, pullMs, cleanupMs, detectMs, pending.inserts.count))
        }
    }
}

extension Duration {
    fileprivate var msValue: Double {
        let c = components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }
}
