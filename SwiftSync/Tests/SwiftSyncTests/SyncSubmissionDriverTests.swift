import XCTest

@testable import SwiftSync

@MainActor
final class SyncSubmissionDriverTests: XCTestCase {
    func testSuccessfulSubmitEndsIdle() async {
        let driver = SyncSubmissionDriver()
        await driver.submit {}
        XCTAssertEqual(driver.phase, .idle)
    }

    func testFailedSubmitBecomesFailedWithLocalizedMessage() async {
        struct LoadError: LocalizedError { var errorDescription: String? { "boom" } }
        let driver = SyncSubmissionDriver()
        await driver.submit { throw LoadError() }
        XCTAssertEqual(driver.phase, .failed(message: "boom"))
    }

    func testBlankErrorDescriptionFallsBackToProvidedMessage() async {
        struct BlankError: LocalizedError { var errorDescription: String? { "   " } }
        let driver = SyncSubmissionDriver(fallbackMessage: "Could not save.")
        await driver.submit { throw BlankError() }
        XCTAssertEqual(driver.phase, .failed(message: "Could not save."))
    }

    func testDismissFailureReturnsToIdle() async {
        struct LoadError: LocalizedError { var errorDescription: String? { "boom" } }
        let driver = SyncSubmissionDriver()
        await driver.submit { throw LoadError() }
        driver.dismissFailure()
        XCTAssertEqual(driver.phase, .idle)
    }
}
