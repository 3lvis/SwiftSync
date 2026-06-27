import SwiftData
import SwiftSync
import XCTest

final class SyncedQueryTests: XCTestCase {
    @MainActor
    func testLoadSucceedsExposingRowsAndLoadedPhase() async throws {
        let container = try SyncContainer(for: InferredTask.self, configurations: .init(isStoredInMemoryOnly: true))
        container.mainContext.insert(InferredTask(id: 1, title: "A"))
        container.mainContext.insert(InferredTask(id: 2, title: "B"))
        try container.mainContext.save()

        let published = SyncedQueryPublisher(
            InferredTask.self, in: container, sortBy: [SortDescriptor(\InferredTask.id)]
        ) {
            // a real screen would sync here; success is all this test needs
        }

        XCTAssertEqual(published.phase, .idle)
        await published.load()

        XCTAssertEqual(published.phase, .loaded)
        XCTAssertEqual(published.rows.map(\.id), [1, 2])
    }

    @MainActor
    func testModelLoadExposesRowAndLoadedPhase() async throws {
        let container = try SyncContainer(for: InferredTask.self, configurations: .init(isStoredInMemoryOnly: true))
        container.mainContext.insert(InferredTask(id: 5, title: "X"))
        try container.mainContext.save()

        let published = SyncedModelPublisher(InferredTask.self, id: 5, in: container) {}

        await published.load()

        XCTAssertEqual(published.phase, .loaded)
        XCTAssertEqual(published.row?.id, 5)
    }

    @MainActor
    func testLoadFailureBecomesFailedPhase() async throws {
        struct LoadError: LocalizedError { var errorDescription: String? { "boom" } }
        let container = try SyncContainer(for: InferredTask.self, configurations: .init(isStoredInMemoryOnly: true))

        let published = SyncedQueryPublisher(InferredTask.self, in: container) {
            throw LoadError()
        }

        await published.load()

        XCTAssertEqual(published.phase, .failed(message: "boom"))
    }

    @MainActor
    func testBlankErrorDescriptionFallsBackToProvidedMessage() async throws {
        struct BlankError: LocalizedError { var errorDescription: String? { "   " } }
        let container = try SyncContainer(for: InferredTask.self, configurations: .init(isStoredInMemoryOnly: true))

        let published = SyncedQueryPublisher(InferredTask.self, in: container, fallbackMessage: "Could not load tasks.") {
            throw BlankError()
        }

        await published.load()

        XCTAssertEqual(published.phase, .failed(message: "Could not load tasks."))
    }
}
