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
    /// The core of the SwiftData-History design: `pendingChanges` reads the store's change history,
    /// counts only locally-authored changes (ignoring inbound/pull writes), and recovers a deleted
    /// row's id from the history tombstone — with zero offline fields on the model.
    func testPendingChangesReadsLocalHistoryAndIgnoresInbound() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("bench.store"))
        let container = try SyncContainer(for: HistoryRow.self, configurations: configuration)
        let now = Date()

        // Inbound (pull) write — author = inboundAuthor. Must be ignored by pendingChanges.
        let inbound = ModelContext(container.modelContainer)
        inbound.author = SwiftSync.inboundAuthor
        inbound.insert(HistoryRow(id: "server-1", title: "From server", updatedAt: now))
        try inbound.save()

        // Local write — default author. Must be detected as a pending insert.
        let local = container.mainContext
        local.insert(HistoryRow(id: "local-1", title: "Made offline", updatedAt: now))
        try local.save()

        let pending = try SwiftSync.pendingChanges(for: HistoryRow.self, in: local)
        XCTAssertEqual(pending.inserts, ["local-1"], "inbound row must be ignored; local insert detected")
        XCTAssertTrue(pending.updates.isEmpty)
        XCTAssertTrue(pending.deletes.isEmpty)

        // Push it so it's "synced" (token advances past its insert); now a later delete is a genuine
        // pending deletion rather than an insert-then-delete the server never saw.
        _ = try await SwiftSync.withPendingChanges(for: HistoryRow.self, in: local) { _ in [] }

        // Delete the synced row with a plain context.delete — the tombstone must yield its id.
        let row = try XCTUnwrap(
            try local.fetch(FetchDescriptor<HistoryRow>(predicate: #Predicate { $0.id == "local-1" })).first)
        local.delete(row)
        try local.save()

        let afterDelete = try SwiftSync.pendingChanges(for: HistoryRow.self, in: local)
        XCTAssertEqual(
            afterDelete.deletes, ["local-1"],
            "deleted row's id must be recovered from the history tombstone")
    }

    /// Opt-in overhead benchmark: how much does a large pull cost under the History design?
    /// Expectation: ~baseline, because the pull writes no extra rows — offline tracking is a *read*
    /// of history at push time, not a write on the pull path.
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

            // Push-side detection over the same store: should be ~empty (all inbound-authored) and fast.
            let detectStart = clock.now
            let pending = try SwiftSync.pendingChanges(for: HistoryRow.self, in: context, since: nil)
            let detectMs = detectStart.duration(to: clock.now).msValue

            print(
                String(
                    format: "[OfflineHistory] rows=%d pullMs=%.1f detectMs=%.1f pendingInserts=%d",
                    count, pullMs, detectMs, pending.inserts.count))
        }
    }
}

extension Duration {
    fileprivate var msValue: Double {
        let c = components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }
}
