import XCTest
import SwiftData
import SwiftSync

final class SyncQueryParentTests: XCTestCase {
    @MainActor
    func testSyncQueryParentInferenceFiltersToParentScope() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: InferredTask.self,
            InferredComment.self,
            configurations: configuration
        )
        let syncContainer = SyncContainer(modelContainer)
        let context = syncContainer.mainContext

        let taskA = InferredTask(id: 1, title: "A")
        let taskB = InferredTask(id: 2, title: "B")
        context.insert(taskA)
        context.insert(taskB)
        context.insert(InferredComment(id: 1, text: "A-1", task: taskA))
        context.insert(InferredComment(id: 2, text: "A-2", task: taskA))
        context.insert(InferredComment(id: 3, text: "B-3", task: taskB))
        try context.save()

        let query = SyncQuery(
            InferredComment.self,
            parent: taskA,
            in: syncContainer,
            sortBy: [SortDescriptor(\InferredComment.id)]
        )

        XCTAssertEqual(query.wrappedValue.map(\.id), [1, 2])
    }

    @MainActor
    func testSyncQueryParentExplicitRelationshipSupportsAmbiguousModels() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: RoleUser.self,
            RoleTicket.self,
            configurations: configuration
        )
        let syncContainer = SyncContainer(modelContainer)
        let context = syncContainer.mainContext

        let userA = RoleUser(id: 1, name: "A")
        let userB = RoleUser(id: 2, name: "B")
        context.insert(userA)
        context.insert(userB)
        context.insert(RoleTicket(id: 10, title: "T-10", assignee: userA, reviewer: userB))
        context.insert(RoleTicket(id: 11, title: "T-11", assignee: userB, reviewer: userA))
        context.insert(RoleTicket(id: 12, title: "T-12", assignee: userA, reviewer: userA))
        try context.save()

        let query = SyncQuery(
            RoleTicket.self,
            parent: userA,
            parentRelationship: \RoleTicket.assignee,
            in: syncContainer,
            sortBy: [SortDescriptor(\RoleTicket.id)]
        )

        XCTAssertEqual(query.wrappedValue.map(\.id), [10, 12])
    }
}
