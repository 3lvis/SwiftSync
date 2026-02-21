import XCTest
import SwiftData
import SwiftSync

@Syncable
@Model
final class SortSugarRecord {
    @Attribute(.unique) var id: String
    var displayName: String
    var isActive: Bool
    var website: URL?

    init(id: String, displayName: String, isActive: Bool, website: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.isActive = isActive
        self.website = website
    }
}

final class SyncQuerySortSugarTests: XCTestCase {
    @MainActor
    func testGeneratedSortDescriptorsApplyStoreLevelOrdering() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SortSugarRecord.self, configurations: configuration)
        let context = ModelContext(container)

        context.insert(SortSugarRecord(id: "3", displayName: "Bob", isActive: false))
        context.insert(SortSugarRecord(id: "2", displayName: "Ada", isActive: true))
        context.insert(SortSugarRecord(id: "1", displayName: "Bob", isActive: true))
        try context.save()

        let sortBy = SortSugarRecord.syncSortDescriptors(for: [\.displayName, \.id])
        let rows = try context.fetch(FetchDescriptor<SortSugarRecord>(sortBy: sortBy))

        XCTAssertEqual(rows.map(\.displayName), ["Ada", "Bob", "Bob"])
        XCTAssertEqual(rows.map(\.id), ["2", "1", "3"])
    }

    @MainActor
    func testGeneratedSortDescriptorsIgnoreUnsupportedKeyPaths() {
        let sortBy = SortSugarRecord.syncSortDescriptors(for: [\.isActive, \.website])
        XCTAssertTrue(sortBy.isEmpty)
    }
}
