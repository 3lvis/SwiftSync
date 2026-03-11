import XCTest

final class DemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchFetchesAndShowsSeededProjects() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.tables["projects.table"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Account Security Controls"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Team Notifications Reliability"].exists)
    }
}

private extension DemoUITests {
    func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SWIFTSYNC_UI_TESTING"] = "1"
        app.launchEnvironment["SWIFTSYNC_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launchEnvironment["SWIFTSYNC_DEMO_SCENARIO"] = "fastStable"
        return app
    }
}
