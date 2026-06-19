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
    /// ⛔️ DO NOT MERGE — a standing tracking test that intentionally **fails today**, and whose branch
    /// must never reach `master` (a red test would block the CI gate). It lives only on its PR.
    ///
    /// SwiftData has no `mergeChanges(fromContextDidSave:)`, so a save on one `ModelContext` does not
    /// refresh an already-registered instance on another (e.g. the `mainContext` instance a SwiftUI view
    /// holds). That gap is the only reason single-object `sync(item:)` applies on the main thread.
    ///
    /// This asserts the behavior we *want* — a cross-context save promptly reflected on the registered
    /// instance — so it is **red on the PR today**. The day a newer SwiftData merges promptly, CI on the
    /// PR turns **green**: the signal to merge this and move single-object (and inbound) sync off the
    /// main thread.
    @MainActor
    func testCrossContextSavePromptlyRefreshesRegisteredInstance() throws {
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

        XCTAssertEqual(
            registered.title, "Edited",
            "Expected to FAIL today: SwiftData did not merge the cross-context save into the registered "
                + "mainContext instance. When this passes, SwiftData merges promptly — single-object "
                + "sync(item:) (and inbound sync) can move off the main thread, and this PR can merge.")
    }
}
