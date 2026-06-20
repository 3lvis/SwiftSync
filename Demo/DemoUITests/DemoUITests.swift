import XCTest

// UI tests are the costliest CI tier, so this suite is intentionally tiny: it holds only journeys that
// exercise genuinely app-layer behavior a DemoCore/SwiftSync/DemoBackend unit cannot (cross-screen
// SwiftUI reactivity, the offline-toggle/auto-sync wiring, the failures-inbox screen). New behavior earns
// coverage below the UI layer first. Rules + the per-test trial: docs/planning/ui-test-trial.md and
// AGENTS.md ("UI tests are a last resort").

private enum DemoSeedUserID {
    static let noahKim = "C3E7A1B2-2001-0000-0000-000000000002"
    static let miaPatel = "C3E7A1B2-2001-0000-0000-000000000003"
    static let liamBrown = "C3E7A1B2-2001-0000-0000-000000000004"
    static let sofiaGarcia = "C3E7A1B2-2001-0000-0000-000000000005"
    static let ethanLee = "C3E7A1B2-2001-0000-0000-000000000006"
}

private enum DemoSeedProjectID {
    static let accountSecurity = "C3E7A1B2-1001-0000-0000-000000000001"
    static let notificationsReliability = "C3E7A1B2-1001-0000-0000-000000000002"
}

private enum DemoSeedTaskID {
    static let sessionTimeout = "C3E7A1B2-3001-0000-0000-000000000001"
    static let securityPolicyPatch = "C3E7A1B2-3001-0000-0000-000000000002"
    static let qaItemList = "C3E7A1B2-3001-0000-0000-000000000003"
    static let duplicatePushFix = "C3E7A1B2-3001-0000-0000-000000000006"
    static let incidentPlaybook = "C3E7A1B2-3001-0000-0000-000000000009"
}

final class DemoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // KEPT (R4): cross-screen reactivity — after a save, the edit must propagate to BOTH the detail and
    // the project-list row (SwiftSync's @SyncQuery driving two SwiftUI views). The update + description
    // normalization logic are unit-tested (OfflinePushTests, TaskFormDescriptionNormalizationTests); the
    // reactive propagation across screens is not unit-coverable without a view host.
    @MainActor
    func testUpdateTaskTitleKeepsProjectAndDetailInSync() throws {
        let app = configuredApp()
        let updatedTitle = uniqueTitle(prefix: "UI Title Update")
        let normalizedDescription = "No description yet."

        app.launch()
        openTaskDetail(
            app,
            projectID: DemoSeedProjectID.accountSecurity,
            taskID: DemoSeedTaskID.sessionTimeout
        )

        openEditTaskForm(app)

        replaceText(in: app.textFields["task-form.title"], with: updatedTitle, app: app)
        replaceText(in: app.textFields["task-form.description"], with: "   ", app: app)
        app.buttons["task-form.save"].tap()

        XCTAssertTrue(app.buttons["task-form.save"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(detailElement(app, id: "task.title").label, updatedTitle)
        XCTAssertEqual(detailElement(app, id: "task.description").label, normalizedDescription)

        goBack(app)
        XCTAssertTrue(app.staticTexts[updatedTitle].exists)
    }

    // KEPT (R4): the offline-success integration is app-layer, not unit-coverable — ContentView's
    // `.onChange(of: isOffline)` auto-drains the queue on reconnect and the pending-count badge is a
    // SwiftUI view. The edit logic itself is unit-tested in OfflinePushTests; this guards the wiring.
    @MainActor
    func testOfflineCreateQueuesThenSyncsOnReconnect() throws {
        let app = configuredApp()
        app.launch()

        // Online: the home screen warms reference data (users + task states) into the cache.
        openProject(app, id: DemoSeedProjectID.accountSecurity)
        XCTAssertTrue(
            app.staticTexts["Add session timeout controls to account settings"].waitForExistence(timeout: 2))
        goBack(app)

        let toggle = app.buttons["offline-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.tap()
        XCTAssertEqual(app.buttons["offline-toggle"].label, "Offline")

        // Create a task offline. With reference data cached, the form fills its defaults and Create enables.
        openProject(app, id: DemoSeedProjectID.accountSecurity)
        openCreateTaskForm(app)
        let title = uniqueTitle(prefix: "Offline Created")
        replaceText(in: app.textFields["task-form.title"], with: title, app: app)
        XCTAssertTrue(app.buttons["task-form.save"].isEnabled, "offline create works with cached reference data")
        app.buttons["task-form.save"].tap()
        XCTAssertTrue(app.buttons["task-form.save"].waitForNonExistence(timeout: 3))

        // It appears locally and is queued.
        XCTAssertTrue(findAfterScrolling(app.staticTexts[title], in: app))
        goBack(app)
        XCTAssertTrue(app.staticTexts["pending-count"].waitForExistence(timeout: 2), "the create is queued")

        // Reconnect: the queue syncs automatically — no button tap.
        app.buttons["offline-toggle"].tap()
        XCTAssertTrue(
            app.staticTexts["pending-count"].waitForNonExistence(timeout: 5),
            "reconnecting auto-syncs the queue")

        // It survived the sync: reopening online (a real refresh) still shows it.
        openProject(app, id: DemoSeedProjectID.accountSecurity)
        XCTAssertTrue(findAfterScrolling(app.staticTexts[title], in: app))
    }

    // KEPT (R4): the failures-inbox screen (FailuresSheet + discard button) is app-layer UI. The failure
    // annotation and discard logic are unit-tested in OfflinePushTests, but the inbox surfacing on a
    // rejected auto-sync is not unit-coverable.
    @MainActor
    func testRejectedOfflineEditAppearsInFailuresInboxAndDiscards() throws {
        let app = configuredApp()
        app.launch()
        openTaskDetail(
            app, projectID: DemoSeedProjectID.accountSecurity, taskID: DemoSeedTaskID.sessionTimeout)

        // Offline: rename the task to a title the server will reject (too long).
        app.buttons["offline-toggle"].tap()
        openEditTaskForm(app)
        replaceText(in: app.textFields["task-form.title"], with: String(repeating: "A", count: 100), app: app)
        app.buttons["task-form.save"].tap()
        XCTAssertTrue(app.buttons["task-form.save"].waitForNonExistence(timeout: 3))

        // Reconnect: auto-sync pushes it, the server rejects it, and it surfaces in the inbox.
        app.buttons["offline-toggle"].tap()
        let failuresButton = app.buttons["failures-button"]
        XCTAssertTrue(
            failuresButton.waitForExistence(timeout: 5), "a rejected change surfaces in the failures inbox")
        failuresButton.tap()

        let discard = app.buttons["failure.discard.\(DemoSeedTaskID.sessionTimeout)"]
        XCTAssertTrue(discard.waitForExistence(timeout: 2), "the failed task is listed with its reason")

        discard.tap()

        // Discarding resolves the failure: the row leaves the inbox.
        XCTAssertTrue(discard.waitForNonExistence(timeout: 5), "discard clears the failure")
    }

}

extension DemoUITests {
    fileprivate func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SWIFTSYNC_UI_TESTING"] = "1"
        app.launchEnvironment["SWIFTSYNC_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["SWIFTSYNC_DEMO_SCENARIO"] = "fastStable"
        return app
    }

    fileprivate func uniqueTitle(prefix: String) -> String {
        "\(prefix) \(UUID().uuidString.prefix(6))"
    }

    fileprivate func openProject(_ app: XCUIApplication, id: String) {
        let row = app.cells["projects.row.\(id)"]
        XCTAssertTrue(row.exists)
        row.tap()
    }

    fileprivate func openTask(_ app: XCUIApplication, id: String) {
        let taskRow = app.descendants(matching: .any)["project.task.\(id)"]
        XCTAssertTrue(taskRow.waitForExistence(timeout: 1))
        taskRow.tap()
    }

    fileprivate func openTaskDetail(_ app: XCUIApplication, projectID: String, taskID: String) {
        openProject(app, id: projectID)
        openTask(app, id: taskID)
        XCTAssertTrue(detailElement(app, id: "task.title").exists)
    }

    fileprivate func detailElement(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    fileprivate func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    fileprivate func openCreateTaskForm(_ app: XCUIApplication) {
        app.buttons["New Task"].tap()
        XCTAssertTrue(app.buttons["task-form.save"].exists)
    }

    fileprivate func openEditTaskForm(_ app: XCUIApplication) {
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["task-form.save"].exists)
    }

    fileprivate func findAfterScrolling(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes where !element.exists {
            if app.tables.firstMatch.exists {
                app.tables.firstMatch.swipeUp()
            } else if app.scrollViews.firstMatch.exists {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return element.exists
    }

    fileprivate func replaceText(in element: XCUIElement, with text: String, app: XCUIApplication) {
        XCTAssertTrue(element.exists)
        element.tap()

        element.press(forDuration: 1.0)

        let selectAllMenuItem = app.menuItems["Select All"]
        let selectAllButton = app.buttons["Select All"]
        if selectAllMenuItem.waitForExistence(timeout: 0.5) {
            selectAllMenuItem.tap()
        } else if selectAllButton.waitForExistence(timeout: 0.5) {
            selectAllButton.tap()
        } else if let currentValue = element.value as? String, !currentValue.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            element.typeText(deleteString)
        }

        element.typeText(text)
    }
}
