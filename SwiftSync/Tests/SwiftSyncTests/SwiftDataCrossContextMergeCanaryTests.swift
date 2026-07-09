import SwiftData
import XCTest

// Pure-SwiftData reproduction — no SwiftSync — of the failure SwiftSync works around with its
// `immediate` flag (commit 5d00aa39). SwiftData has no `mergeChanges(fromContextDidSave:)`, so a save
// on one `ModelContext` does not refresh an already-registered instance on another (e.g. the
// `mainContext` row a SwiftUI view holds). That is the "offline edit doesn't update the list" bug;
// SwiftSync sidesteps it by applying local writes on the main context. This test isolates the raw
// SwiftData mechanics, with nothing from SwiftSync involved.
//
// ⛔️ DO NOT MERGE. It asserts the behavior we *want* (a cross-context save reflected on the registered
// instance), so it is RED today and turns GREEN the day SwiftData merges cross-context saves promptly —
// the signal that the `immediate`/main-apply workaround can be retired. Lives on its PR only; the branch
// must never reach `master` (a red test would block the CI gate).

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
    @MainActor
    func testCrossContextSaveRefreshesRegisteredInstance() throws {
        let container = try ModelContainer(
            for: CrossContextCanaryNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))

        // A view holds a row registered in the main context.
        let mainContext = container.mainContext
        mainContext.insert(CrossContextCanaryNote(id: "n1", title: "Original"))
        try mainContext.save()
        let registered = try XCTUnwrap(mainContext.fetch(FetchDescriptor<CrossContextCanaryNote>()).first)

        // A second context — the "background import" path — edits the same row and saves.
        let backgroundContext = ModelContext(container)
        let background = try XCTUnwrap(
            backgroundContext.fetch(FetchDescriptor<CrossContextCanaryNote>()).first)
        background.title = "Edited"
        try backgroundContext.save()

        // The behavior we want: the registered instance reflects the saved edit. Fails today — SwiftData
        // does not merge the background save into it. Passes when SwiftData gains a prompt cross-context
        // merge, at which point the immediate/main-apply workaround can be retired.
        XCTAssertEqual(
            registered.title, "Edited",
            "Expected to FAIL today: SwiftData did not merge the background-context save into the "
                + "registered mainContext instance. When this passes, the immediate/main-apply workaround "
                + "can be retired.")
    }
}
