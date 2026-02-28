import XCTest
import SwiftData
import SwiftSync

@Syncable
@Model
final class ValidationMissingAnchorTask {
    @Attribute(.unique) var id: Int
    var tags: [ValidationMissingAnchorTag]

    init(id: Int, tags: [ValidationMissingAnchorTag] = []) {
        self.id = id
        self.tags = tags
    }
}

@Syncable
@Model
final class ValidationMissingAnchorTag {
    @Attribute(.unique) var id: Int
    var tasks: [ValidationMissingAnchorTask]

    init(id: Int, tasks: [ValidationMissingAnchorTask] = []) {
        self.id = id
        self.tasks = tasks
    }
}

@Syncable
@Model
final class ValidationAnchoredTask {
    @Attribute(.unique) var id: Int
    @Relationship(inverse: \ValidationAnchoredTag.tasks)
    var tags: [ValidationAnchoredTag]

    init(id: Int, tags: [ValidationAnchoredTag] = []) {
        self.id = id
        self.tags = tags
    }
}

@Syncable
@Model
final class ValidationAnchoredTag {
    @Attribute(.unique) var id: Int
    var tasks: [ValidationAnchoredTask]

    init(id: Int, tasks: [ValidationAnchoredTask] = []) {
        self.id = id
        self.tasks = tasks
    }
}

@Syncable
@Model
final class ValidationOneToManyProject {
    @Attribute(.unique) var id: Int
    var tasks: [ValidationOneToManyTask]

    init(id: Int, tasks: [ValidationOneToManyTask] = []) {
        self.id = id
        self.tasks = tasks
    }
}

@Syncable
@Model
final class ValidationOneToManyTask {
    @Attribute(.unique) var id: Int
    var project: ValidationOneToManyProject?

    init(id: Int, project: ValidationOneToManyProject? = nil) {
        self.id = id
        self.project = project
    }
}

final class SyncContainerSchemaValidationTests: XCTestCase {
    @MainActor
    func testSchemaValidationFailsForManyToManyPairWithoutExplicitInverseAnchor() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        XCTAssertThrowsError(
            try SyncContainer(
                for: ValidationMissingAnchorTask.self,
                ValidationMissingAnchorTag.self,
                configurations: configuration
            )
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("many-to-many"), "Expected many-to-many validation error, got: \(message)")
            XCTAssertTrue(message.contains("ValidationMissingAnchorTask.tags") || message.contains("ValidationMissingAnchorTag.tasks"))
        }
    }

    @MainActor
    func testSchemaValidationAllowsManyToManyPairWithOneExplicitInverseAnchor() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        _ = try SyncContainer(
            for: ValidationAnchoredTask.self,
            ValidationAnchoredTag.self,
            configurations: configuration
        )
    }

    @MainActor
    func testSchemaValidationAllowsOneToManyWithoutExplicitInverse() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        _ = try SyncContainer(
            for: ValidationOneToManyProject.self,
            ValidationOneToManyTask.self,
            configurations: configuration
        )
    }
}
