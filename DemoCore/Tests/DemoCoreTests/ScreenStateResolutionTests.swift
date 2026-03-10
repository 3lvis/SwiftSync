import XCTest
@testable import DemoCore

final class ScreenStateResolutionTests: XCTestCase {

    func testProjectsListStatusState_loadingWithoutRows_showsLoading() {
        XCTAssertEqual(
            resolveProjectsListStatusState(loadState: .loading, hasRows: false),
            .loading
        )
    }

    func testProjectsListStatusState_loadingWithRows_hidesStatus() {
        XCTAssertEqual(
            resolveProjectsListStatusState(loadState: .loading, hasRows: true),
            .hidden
        )
    }

    func testProjectsListStatusState_loadedWithoutRows_showsEmpty() {
        XCTAssertEqual(
            resolveProjectsListStatusState(loadState: .loaded, hasRows: false),
            .empty
        )
    }

    func testProjectsListStatusState_error_showsError() {
        XCTAssertEqual(
            resolveProjectsListStatusState(
                loadState: .error(ErrorPresentationState(message: "boom")),
                hasRows: false
            ),
            .error(ErrorPresentationState(message: "boom"))
        )
    }

    func testProjectDetailContentState_loadingWithoutCachedContent_showsLoading() {
        XCTAssertEqual(
            resolveProjectDetailContentState(loadState: .loading, hasProject: false, hasTasks: false),
            .loading
        )
    }

    func testProjectDetailContentState_loadingWithCachedProject_showsContent() {
        XCTAssertEqual(
            resolveProjectDetailContentState(loadState: .loading, hasProject: true, hasTasks: false),
            .content
        )
    }

    func testProjectDetailContentState_loadingWithCachedTasks_showsContent() {
        XCTAssertEqual(
            resolveProjectDetailContentState(loadState: .loading, hasProject: false, hasTasks: true),
            .content
        )
    }

    func testProjectDetailContentState_loadedWithoutContent_showsNotFound() {
        XCTAssertEqual(
            resolveProjectDetailContentState(loadState: .loaded, hasProject: false, hasTasks: false),
            .notFound
        )
    }

    func testTaskDetailContentState_loadingWithoutCachedTask_showsLoading() {
        XCTAssertEqual(
            resolveTaskDetailContentState(loadState: .loading, hasTask: false),
            .loading
        )
    }

    func testTaskDetailContentState_loadingWithCachedTask_showsContent() {
        XCTAssertEqual(
            resolveTaskDetailContentState(loadState: .loading, hasTask: true),
            .content
        )
    }

    func testTaskDetailContentState_loadedWithoutTask_showsNotFound() {
        XCTAssertEqual(
            resolveTaskDetailContentState(loadState: .loaded, hasTask: false),
            .notFound
        )
    }

    func testTaskFormOptionsState_loadingWithoutOptions_showsLoading() {
        XCTAssertEqual(
            resolveTaskFormOptionsState(loadState: .loading, hasOptions: false),
            .loading
        )
    }

    func testTaskFormOptionsState_loadingWithCachedOptions_showsAvailable() {
        XCTAssertEqual(
            resolveTaskFormOptionsState(loadState: .loading, hasOptions: true),
            .available
        )
    }

    func testTaskFormOptionsState_loadedWithoutOptions_showsUnavailable() {
        XCTAssertEqual(
            resolveTaskFormOptionsState(loadState: .loaded, hasOptions: false),
            .unavailable
        )
    }

    func testTaskFormOptionsState_errorWithoutOptions_showsUnavailable() {
        XCTAssertEqual(
            resolveTaskFormOptionsState(
                loadState: .error(ErrorPresentationState(message: "boom")),
                hasOptions: false
            ),
            .unavailable
        )
    }
}
