import XCTest

private enum DemoUITestPlan {
    /*
     Source of truth for Demo UI automation planning.

     Purpose of the Demo app:
     - prove SwiftSync works in real app flows, not only isolated unit tests
     - show project list -> project detail -> task detail -> create/edit/delete behavior
     - act as an integration regression surface for synced reads, writes, and relationships

     Testing rule:
     - tests should map to user goals, not to screen checkpoints
     - navigation assertions only matter when they support a larger journey
     - add scaffolding only when the next real journey needs it

     Implemented coverage:
     - bootstrap smoke: launch and confirm the canonical seeded project list loads
     - journey: browse work and inspect task details
       path:
       1. open app
       2. open "Account Security Controls"
       3. open "Add session timeout controls to account settings"
       4. verify title, assignee, author, and seeded checklist items

     Planned journeys live below as commented-out test stubs so the file itself
     stays the active UI automation roadmap.
     */
}

private enum DemoSeedUserID {
    static let noahKim = "C3E7A1B2-2001-0000-0000-000000000002"
    static let miaPatel = "C3E7A1B2-2001-0000-0000-000000000003"
    static let sofiaGarcia = "C3E7A1B2-2001-0000-0000-000000000005"
    static let ethanLee = "C3E7A1B2-2001-0000-0000-000000000006"
}

final class DemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // User journey: browse work and inspect synced task details.
    @MainActor
    func testProjectAndTaskDetailShowSeededContent() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Account Security Controls"].waitForExistence(timeout: 10))
        app.staticTexts["Account Security Controls"].tap()

        XCTAssertTrue(app.staticTexts["Add session timeout controls to account settings"].waitForExistence(timeout: 10))

        app.staticTexts["Add session timeout controls to account settings"].tap()

        XCTAssertTrue(app.staticTexts["task.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task.title"].label, "Add session timeout controls to account settings")
        XCTAssertEqual(app.staticTexts["task.assignee"].label, "Ava Martinez")
        XCTAssertEqual(app.staticTexts["task.author"].label, "Ava Martinez")
        XCTAssertTrue(app.staticTexts["Gather requirements"].exists)
        XCTAssertTrue(app.staticTexts["Draft implementation plan"].exists)
    }

    @MainActor
    func testUpdateTaskTitleKeepsProjectAndDetailInSync() throws {
        let app = configuredApp()
        let updatedTitle = uniqueTitle(prefix: "UI Title Update")

        app.launch()
        openTaskDetail(
            app,
            projectTitle: "Account Security Controls",
            taskTitle: "Add session timeout controls to account settings"
        )

        openEditTaskForm(app)

        replaceText(in: app.textViews["task-form.title"], with: updatedTitle, app: app)
        app.buttons["task-form.save"].tap()

        XCTAssertTrue(app.staticTexts["task.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task.title"].label, updatedTitle)

        goBack(app)
        XCTAssertTrue(app.staticTexts[updatedTitle].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCreateTaskInsideProject() throws {
        let app = configuredApp()
        let createdTitle = uniqueTitle(prefix: "UI Created Task")

        app.launch()
        openProject(app, title: "Account Security Controls")

        openCreateTaskForm(app)

        let saveButton = app.buttons["task-form.save"]
        XCTAssertFalse(saveButton.isEnabled)

        replaceText(in: app.textViews["task-form.title"], with: createdTitle, app: app)
        XCTAssertTrue(waitUntilEnabled(saveButton))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts[createdTitle].waitForExistence(timeout: 10))
        app.staticTexts[createdTitle].tap()

        XCTAssertTrue(app.staticTexts["task.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task.title"].label, createdTitle)
    }

    @MainActor
    func testEditTaskItemsFlow() throws {
        let app = configuredApp()
        let addedItemTitle = uniqueTitle(prefix: "UI Added Item")
        let renamedItemTitle = "Relaunch flow after timeout"
        let deletedItemTitle = "Offline to online recovery"

        app.launch()
        openTaskDetail(
            app,
            projectTitle: "Account Security Controls",
            taskTitle: "Write QA item list for forced re-auth scenarios"
        )

        openEditTaskForm(app)

        replaceText(in: app.textFields["task-form.items.new-title"], with: addedItemTitle, app: app)
        app.buttons["task-form.items.add"].tap()

        replaceText(in: app.textFields["task-form.items.0.title"], with: renamedItemTitle, app: app)
        app.buttons["task-form.items.1.delete"].tap()
        app.buttons["task-form.save"].tap()

        XCTAssertTrue(app.staticTexts[renamedItemTitle].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[addedItemTitle].exists)
        XCTAssertFalse(app.staticTexts[deletedItemTitle].exists)
    }

    @MainActor
    func testEditTaskPeopleFlow() throws {
        let app = configuredApp()

        app.launch()
        openTaskDetail(
            app,
            projectTitle: "Team Notifications Reliability",
            taskTitle: "Fix duplicate push preference sync after reconnect"
        )

        openEditTaskForm(app)

        tapAfterScrolling(app.buttons["task-form.assignee.\(DemoSeedUserID.miaPatel)"], in: app)
        tapAfterScrolling(app.buttons["task-form.reviewer.\(DemoSeedUserID.noahKim)"], in: app)
        tapAfterScrolling(app.buttons["task-form.reviewer.\(DemoSeedUserID.sofiaGarcia)"], in: app)
        tapAfterScrolling(app.buttons["task-form.watcher.\(DemoSeedUserID.ethanLee)"], in: app)
        tapAfterScrolling(app.buttons["task-form.watcher.\(DemoSeedUserID.sofiaGarcia)"], in: app)
        app.buttons["task-form.save"].tap()

        XCTAssertTrue(app.staticTexts["task.assignee"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["task.assignee"].label, "Mia Patel")
        XCTAssertTrue(app.staticTexts["Sofia Garcia"].exists)
        XCTAssertFalse(app.staticTexts["Noah Kim"].exists)
        XCTAssertFalse(app.staticTexts["Ethan Lee"].exists)
    }

    // TODO: User journey: remove work safely.
    // Purpose:
    // - prove destructive mutation through the sync layer
    // - prove the scoped project list refreshes after delete
    //
    // @MainActor
    // func testDeleteTaskFromProject() throws {}

    // TODO: Edge journey: cancel create.
    // Purpose:
    // - prove leaving the create form does not persist partial draft data
    //
    // @MainActor
    // func testCancelCreateDoesNotPersistTask() throws {}

    // TODO: Edge journey: cancel edit.
    // Purpose:
    // - prove leaving the edit form does not mutate the original task
    //
    // @MainActor
    // func testCancelEditKeepsOriginalTaskValues() throws {}

    // TODO: Edge journey: normalize empty description.
    // Purpose:
    // - prove clearing description content saves as "No description yet."
    //
    // @MainActor
    // func testEditTaskNormalizesEmptyDescription() throws {}

    // TODO: Edge journey: assign the seeded unassigned task.
    // Purpose:
    // - prove unassigned -> assigned transitions render correctly in task detail
    //
    // @MainActor
    // func testAssignUnassignedTask() throws {}

    // TODO: Edge journey: remove all reviewers or watchers.
    // Purpose:
    // - prove relationship clearing persists and task detail falls back to "None"
    //
    // @MainActor
    // func testClearTaskReviewersOrWatchers() throws {}

    // TODO: Edge journey: cancel delete at the confirmation alert.
    // Purpose:
    // - prove destructive intent is not applied unless confirmed
    //
    // @MainActor
    // func testCancelDeleteKeepsTask() throws {}

    // TODO: Edge journey: repeat the same edit flow twice.
    // Purpose:
    // - prove repeated saves continue to propagate correctly
    //
    // @MainActor
    // func testRepeatedTaskEditFlow() throws {}

    // TODO: Failure journey: empty project list.
    // Purpose:
    // - prove the app communicates there is no work yet
    //
    // @MainActor
    // func testBrowseWorkWithEmptyProjectList() throws {}

    // TODO: Failure journey: empty project tasks.
    // Purpose:
    // - prove a project with no tasks renders its scoped empty state clearly
    //
    // @MainActor
    // func testBrowseProjectWithNoTasks() throws {}

    // TODO: Failure journey: task with no items.
    // Purpose:
    // - prove empty task-detail checklist state is rendered clearly
    //
    // @MainActor
    // func testOpenTaskWithNoItems() throws {}

    // TODO: Failure journey: save failure.
    // Purpose:
    // - prove failed writes leave the form open and show a clear error
    //
    // @MainActor
    // func testEditTaskSaveFailure() throws {}

    // TODO: Failure journey: delete failure.
    // Purpose:
    // - prove failed deletes keep the task visible and show a clear error
    //
    // @MainActor
    // func testDeleteTaskFailure() throws {}

    // TODO: Failure journey: offline or slow browsing/editing.
    // Purpose:
    // - prove the demo communicates loading and failure states during realistic use
    //
    // @MainActor
    // func testBrowseOrEditUnderOfflineOrSlowConditions() throws {}
}

private extension DemoUITests {
    func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SWIFTSYNC_UI_TESTING"] = "1"
        app.launchEnvironment["SWIFTSYNC_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["SWIFTSYNC_DEMO_SCENARIO"] = "fastStable"
        return app
    }

    func uniqueTitle(prefix: String) -> String {
        "\(prefix) \(UUID().uuidString.prefix(6))"
    }

    func openProject(_ app: XCUIApplication, title: String) {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.staticTexts[title].tap()
    }

    func openTaskDetail(_ app: XCUIApplication, projectTitle: String, taskTitle: String) {
        openProject(app, title: projectTitle)
        XCTAssertTrue(app.staticTexts[taskTitle].waitForExistence(timeout: 10))
        app.staticTexts[taskTitle].tap()
        XCTAssertTrue(app.staticTexts["task.title"].waitForExistence(timeout: 10))
    }

    func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    func openCreateTaskForm(_ app: XCUIApplication) {
        app.buttons["New Task"].tap()
        XCTAssertTrue(app.buttons["task-form.save"].waitForExistence(timeout: 10))
    }

    func openEditTaskForm(_ app: XCUIApplication) {
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["task-form.save"].waitForExistence(timeout: 10))
    }

    func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func tapAfterScrolling(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        for _ in 0..<maxSwipes where !element.isHittable {
            if app.tables.firstMatch.exists {
                app.tables.firstMatch.swipeUp()
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else if app.otherElements["task-form"].exists {
                app.otherElements["task-form"].swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists)
        element.tap()
    }

    func replaceText(in element: XCUIElement, with text: String, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        element.tap()

        if let currentValue = element.value as? String, !currentValue.isEmpty {
            element.press(forDuration: 1.0)

            if app.menuItems["Select All"].waitForExistence(timeout: 2) {
                app.menuItems["Select All"].tap()
            } else if app.buttons["Select All"].waitForExistence(timeout: 2) {
                app.buttons["Select All"].tap()
            } else {
                let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
                element.typeText(deleteString)
            }
        }

        element.typeText(text)
    }
}
