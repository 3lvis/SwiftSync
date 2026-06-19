import SwiftData
import XCTest

@testable import SwiftSync

@Model
final class CrossContextCanaryNote {
    @Attribute(.unique) var id: String
    var title: String
    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

final class SwiftDataCrossContextMergeCanaryTests: XCTestCase {
    /// CANARY for the SwiftData limitation SwiftSync works around. SwiftData has no
    /// `mergeChanges(fromContextDidSave:)`, so a save on one `ModelContext` does **not** promptly refresh
    /// an already-registered instance on another context (e.g. the `mainContext` instance a SwiftUI view
    /// holds). That gap is the *only* reason single-object `sync(item:)` applies on the main thread
    /// (see the PR that removed `SyncContext`).
    ///
    /// The test asserts the *broken* behavior inside `XCTExpectFailure`: today the registered instance
    /// stays stale, the inner assertion fails, and the expectation is satisfied (this test passes). If a
    /// future SwiftData merges cross-context saves promptly, the inner assertion will start **passing** —
    /// the expectation is then unmet and this test **fails**, signalling that single-object (and inbound)
    /// sync can move off the main thread.
    @MainActor
    func testCrossContextSaveDoesNotPromptlyRefreshRegisteredInstance() throws {
        let container = try ModelContainer(
            for: CrossContextCanaryNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))

        let mainContext = container.mainContext
        mainContext.insert(CrossContextCanaryNote(id: "n1", title: "Original"))
        try mainContext.save()

        // The instance a live query / SwiftUI view would be holding.
        let registered = try XCTUnwrap(mainContext.fetch(FetchDescriptor<CrossContextCanaryNote>()).first)

        // Update the same row through a separate context and save — with no runloop turn in between.
        let otherContext = ModelContext(container)
        let other = try XCTUnwrap(otherContext.fetch(FetchDescriptor<CrossContextCanaryNote>()).first)
        other.title = "Edited"
        try otherContext.save()

        XCTExpectFailure(
            "SwiftData still does not auto-merge a cross-context save into a registered mainContext instance"
        ) {
            XCTAssertEqual(
                registered.title, "Edited",
                "If this passes, SwiftData now merges cross-context saves promptly — single-object "
                    + "sync(item:) (and inbound sync) can move off the main thread.")
        }
    }
}
